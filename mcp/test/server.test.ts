import assert from "node:assert/strict";
import test from "node:test";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";

import { createHueworksMcpServer, type HueworksApi } from "../src/index.js";

test("MCP server advertises safe read tools, resolves names, and maps explicit control input to REST semantics", async () => {
  const api = new FakeHueworksApi();
  const server = createHueworksMcpServer(api);
  const client = new Client({ name: "hueworks-mcp-test-client", version: "0.1.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

  await server.connect(serverTransport);
  await client.connect(clientTransport);

  const { tools } = await client.listTools();
  const statusTool = tools.find((tool) => tool.name === "hueworks_status");
  const searchTool = tools.find((tool) => tool.name === "hueworks_search_entities");
  const controlTool = tools.find((tool) => tool.name === "hueworks_control_entity");

  assert.equal(statusTool?.annotations?.readOnlyHint, true);
  assert.equal(searchTool?.annotations?.readOnlyHint, true);
  assert.equal(controlTool?.annotations?.readOnlyHint, false);
  assert.equal(controlTool?.annotations?.destructiveHint, false);

  const searchResult = await client.callTool({
    name: "hueworks_search_entities",
    arguments: { query: "Office Lamps", kind: "group", area_id: 7 },
  });

  assert.equal("isError" in searchResult ? searchResult.isError : undefined, undefined);
  assert.ok("structuredContent" in searchResult);
  assert.deepEqual(searchResult.structuredContent, {
    query: "office lamps",
    exact_match_count: 1,
    exact_controllable_match_count: 1,
    results: [{ id: 8, kind: "group", match: "exact", controllable: true }],
  });
  assert.deepEqual(api.searchRequests, [{ query: "Office Lamps", kind: "group", areaId: 7 }]);

  const result = await client.callTool({
    name: "hueworks_control_entity",
    arguments: { kind: "light", id: 7, power: "on" },
  });

  assert.equal("isError" in result ? result.isError : undefined, undefined);
  assert.ok("structuredContent" in result);
  assert.deepEqual(result.structuredContent, { operation: "light_control", trace_id: "api-control-7" });
  assert.deepEqual(api.controlRequests, [{ kind: "light", id: 7, command: { power: "on" } }]);

  await client.close();
  await server.close();
});

class FakeHueworksApi implements HueworksApi {
  controlRequests: Array<{ kind: "light" | "group"; id: number; command: Record<string, unknown> }> = [];
  searchRequests: Array<{ query: string; kind?: "light" | "group"; areaId?: number; limit?: number }> = [];

  async status(): Promise<unknown> {
    return { api_version: "v1" };
  }

  async listAreas(): Promise<unknown> {
    return { areas: [] };
  }

  async area(): Promise<unknown> {
    return { kind: "area" };
  }

  async entity(): Promise<unknown> {
    return { kind: "light" };
  }

  async searchEntities(filters: {
    query: string;
    kind?: "light" | "group";
    areaId?: number;
    limit?: number;
  }): Promise<unknown> {
    this.searchRequests.push(filters);

    return {
      query: "office lamps",
      exact_match_count: 1,
      exact_controllable_match_count: 1,
      results: [{ id: 8, kind: "group", match: "exact", controllable: true }],
    };
  }

  async controlTrace(): Promise<unknown> {
    return { events: [] };
  }

  async activateScene(): Promise<unknown> {
    return { operation: "scene_activate" };
  }

  async deactivateAreaScene(): Promise<unknown> {
    return { operation: "area_scene_deactivate" };
  }

  async controlEntity(
    kind: "light" | "group",
    id: number,
    command: Record<string, unknown>,
  ): Promise<unknown> {
    this.controlRequests.push({ kind, id, command });
    return { operation: "light_control", trace_id: "api-control-7" };
  }

  async refreshPhysicalState(): Promise<unknown> {
    return { operation: "physical_state_refresh" };
  }
}
