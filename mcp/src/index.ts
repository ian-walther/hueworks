import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import {
  HueworksApiClient,
  HueworksApiError,
  type EntityKind,
  type HueworksApi,
  type TraceFilters,
} from "./api_client.js";

export type { HueworksApi } from "./api_client.js";

const entityKindSchema = z.enum(["light", "group"]);
const positiveInteger = z.number().int().positive();

const controlInputSchema = z
  .object({
    kind: entityKindSchema,
    id: positiveInteger,
    power: z.enum(["on", "off"]).optional(),
    brightness: z.number().int().min(1).max(100).optional(),
    kelvin: z.number().int().positive().optional(),
    color: z
      .object({
        hue: z.number().int().min(0).max(360),
        saturation: z.number().int().min(0).max(100),
      })
      .strict()
      .optional(),
  })
  .strict()
  .superRefine((value, context) => {
    const controls = [value.power, value.brightness, value.kelvin, value.color].filter(
      (control) => control !== undefined,
    );

    if (controls.length !== 1) {
      context.addIssue({
        code: "custom",
        message: "Provide exactly one of power, brightness, kelvin, or color.",
      });
    }
  });

export function createHueworksMcpServer(api: HueworksApi): McpServer {
  const server = new McpServer({ name: "hueworks", version: "0.1.0" });

  server.registerTool(
    "hueworks_status",
    {
      description: "Read HueWorks runtime readiness, enabled integrations, and concise entity counts.",
      annotations: readOnlyAnnotations,
    },
    async () => toolResult(() => api.status()),
  );

  server.registerTool(
    "hueworks_list_rooms",
    {
      description: "List HueWorks rooms with active-scene summaries and entity counts.",
      annotations: readOnlyAnnotations,
    },
    async () => toolResult(() => api.listRooms()),
  );

  server.registerTool(
    "hueworks_get_room",
    {
      description:
        "Read one room. Physical state is observed hardware state and may be null; desired state is HueWorks intent.",
      inputSchema: z.object({
        room_id: positiveInteger,
        include_diagnostics: z.boolean().optional().default(false),
      }),
      annotations: readOnlyAnnotations,
    },
    async ({ room_id, include_diagnostics }) => toolResult(() => api.room(room_id, include_diagnostics)),
  );

  server.registerTool(
    "hueworks_get_entity",
    {
      description:
        "Read one light or group. By default this includes safe diagnostics; do not treat missing physical state as off.",
      inputSchema: z.object({
        kind: entityKindSchema,
        id: positiveInteger,
        include_diagnostics: z.boolean().optional().default(true),
      }),
      annotations: readOnlyAnnotations,
    },
    async ({ kind, id, include_diagnostics }) =>
      toolResult(() => api.entity(kind, id, include_diagnostics)),
  );

  server.registerTool(
    "hueworks_get_control_trace",
    {
      description:
        "Read recent bounded control lifecycle evidence. The trace buffer is in memory and is not a durable history.",
      inputSchema: z.object({
        trace_id: z.string().min(1).max(200).optional(),
        room_id: positiveInteger.optional(),
        entity_kind: entityKindSchema.optional(),
        entity_id: positiveInteger.optional(),
        source: z.string().min(1).max(200).optional(),
        limit: z.number().int().min(1).max(100).optional(),
      }),
      annotations: readOnlyAnnotations,
    },
    async (arguments_) =>
      toolResult(() =>
        api.controlTrace({
          traceId: arguments_.trace_id,
          roomId: arguments_.room_id,
          entityKind: arguments_.entity_kind,
          entityId: arguments_.entity_id,
          source: arguments_.source,
          limit: arguments_.limit,
        }),
      ),
  );

  server.registerTool(
    "hueworks_activate_scene",
    {
      description:
        "Activate or reapply a specific HueWorks scene. This writes desired state and queues normal control work; it never toggles.",
      inputSchema: z.object({ scene_id: positiveInteger }),
      annotations: writeAnnotations,
    },
    async ({ scene_id }) => toolResult(() => api.activateScene(scene_id)),
  );

  server.registerTool(
    "hueworks_deactivate_room_scene",
    {
      description:
        "Explicitly clear a room's active HueWorks scene. This does not toggle a scene and does not directly dispatch hardware commands.",
      inputSchema: z.object({ room_id: positiveInteger }),
      annotations: writeAnnotations,
    },
    async ({ room_id }) => toolResult(() => api.deactivateRoomScene(room_id)),
  );

  server.registerTool(
    "hueworks_control_entity",
    {
      description:
        "Apply exactly one explicit manual control to an enabled light or group. This writes desired state through HueWorks normal scene/manual rules and may be rejected while a scene is active.",
      inputSchema: controlInputSchema,
      annotations: writeAnnotations,
    },
    async (arguments_) => {
      const { kind, id, ...command } = arguments_;
      return toolResult(() => api.controlEntity(kind, id, command));
    },
  );

  server.registerTool(
    "hueworks_refresh_physical_state",
    {
      description:
        "Request an asynchronous observed-state refresh from existing bridges. It does not change desired state; query traces and physical state afterwards.",
      annotations: writeAnnotations,
    },
    async () => toolResult(() => api.refreshPhysicalState()),
  );

  return server;
}

export async function main(environment: NodeJS.ProcessEnv = process.env): Promise<void> {
  const api = HueworksApiClient.fromEnvironment(environment);
  const server = createHueworksMcpServer(api);
  await server.connect(new StdioServerTransport());
}

const readOnlyAnnotations = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};

const writeAnnotations = {
  readOnlyHint: false,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false,
};

async function toolResult(operation: () => Promise<unknown>) {
  try {
    const payload = await operation();
    const structuredContent = structured(payload);

    return {
      content: [{ type: "text" as const, text: conciseSummary(payload) }],
      structuredContent,
    };
  } catch (error) {
    const message =
      error instanceof HueworksApiError
        ? `HueWorks API ${error.status}: ${error.code}: ${error.message}`
        : error instanceof Error
          ? error.message
          : "HueWorks MCP request failed.";

    return {
      content: [{ type: "text" as const, text: message }],
      isError: true,
    };
  }
}

function structured(payload: unknown): Record<string, unknown> {
  return isRecord(payload) ? payload : { value: payload };
}

function conciseSummary(payload: unknown): string {
  if (isRecord(payload)) {
    const operation = payload.operation;
    const traceId = payload.trace_id;

    if (typeof operation === "string" && typeof traceId === "string") {
      return `${operation} accepted. Trace: ${traceId}`;
    }
  }

  return JSON.stringify(payload);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isEntrypoint(): boolean {
  return process.argv[1] !== undefined && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1]);
}

if (isEntrypoint()) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : "HueWorks MCP server failed to start.";
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  });
}
