import assert from "node:assert/strict";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import test from "node:test";

import { HueworksApiClient, HueworksApiError } from "../src/api_client.js";

type RecordedRequest = {
  method: string | undefined;
  url: string | undefined;
  authorization: string | undefined;
  body: unknown;
};

test("API client sends bearer-authenticated, explicit control requests", async (t) => {
  const requests: RecordedRequest[] = [];
  const server = await startFixtureServer(requests);
  t.after(() => close(server));

  const client = new HueworksApiClient({
    baseUrl: serverUrl(server),
    token: "test-api-token",
  });

  assert.deepEqual(await client.status(), { api_version: "v1" });

  assert.deepEqual(await client.controlEntity("light", 42, { power: "on" }), {
    operation: "light_control",
    trace_id: "api-42",
  });

  assert.deepEqual(requests, [
    {
      method: "GET",
      url: "/api/v1/status",
      authorization: "Bearer test-api-token",
      body: undefined,
    },
    {
      method: "POST",
      url: "/api/v1/lights/42/control",
      authorization: "Bearer test-api-token",
      body: { power: "on" },
    },
  ]);
});

test("API client encodes trace filters and preserves HueWorks error details", async (t) => {
  const requests: RecordedRequest[] = [];
  const server = await startFixtureServer(requests);
  t.after(() => close(server));

  const client = new HueworksApiClient({
    baseUrl: serverUrl(server),
    token: "test-api-token",
  });

  assert.deepEqual(
    await client.controlTrace({ entityKind: "group", entityId: 9, limit: 20 }),
    { events: [] },
  );

  await assert.rejects(
    () => client.get("/api/v1/error"),
    (error: unknown) => {
      if (error instanceof HueworksApiError) {
        assert.equal(error.status, 409);
        assert.equal(error.code, "scene_active_manual_adjustment_not_allowed");
        assert.deepEqual(error.details, { area_id: 4 });
        return true;
      }

      return false;
    },
  );

  assert.equal(requests[0]?.url, "/api/v1/traces?entity_kind=group&entity_id=9&limit=20");
});

test("API client encodes entity lookup filters", async (t) => {
  const requests: RecordedRequest[] = [];
  const server = await startFixtureServer(requests);
  t.after(() => close(server));

  const client = new HueworksApiClient({
    baseUrl: serverUrl(server),
    token: "test-api-token",
  });

  assert.deepEqual(
    await client.searchEntities({ query: "Office Lamps", kind: "group", areaId: 4, limit: 10 }),
    { query: "office lamps", results: [] },
  );

  assert.deepEqual(requests[0], {
    method: "GET",
    url: "/api/v1/entities?query=Office+Lamps&kind=group&area_id=4&limit=10",
    authorization: "Bearer test-api-token",
    body: undefined,
  });
});

async function startFixtureServer(requests: RecordedRequest[]): Promise<Server> {
  const server = createServer(async (request, response) => {
    const body = await readJsonBody(request);

    requests.push({
      method: request.method,
      url: request.url,
      authorization: request.headers.authorization,
      body,
    });

    switch (request.url) {
      case "/api/v1/status":
        return sendJson(response, 200, { api_version: "v1" });

      case "/api/v1/lights/42/control":
        return sendJson(response, 200, { operation: "light_control", trace_id: "api-42" });

      case "/api/v1/traces?entity_kind=group&entity_id=9&limit=20":
        return sendJson(response, 200, { events: [] });

      case "/api/v1/entities?query=Office+Lamps&kind=group&area_id=4&limit=10":
        return sendJson(response, 200, { query: "office lamps", results: [] });

      case "/api/v1/error":
        return sendJson(response, 409, {
          error: {
            code: "scene_active_manual_adjustment_not_allowed",
            message: "Manual adjustment is blocked.",
            details: { area_id: 4 },
          },
        });

      default:
        return sendJson(response, 404, { error: { code: "not_found", message: "Not found." } });
    }
  });

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });

  return server;
}

function readJsonBody(request: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => chunks.push(chunk));
    request.on("error", reject);
    request.on("end", () => {
      const body = Buffer.concat(chunks).toString("utf8");
      resolve(body === "" ? undefined : JSON.parse(body));
    });
  });
}

function sendJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function serverUrl(server: Server): string {
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  return `http://127.0.0.1:${address.port}`;
}

function close(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}
