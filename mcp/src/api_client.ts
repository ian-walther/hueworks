export type EntityKind = "light" | "group";

export type TraceFilters = {
  traceId?: string;
  areaId?: number;
  entityKind?: EntityKind;
  entityId?: number;
  source?: string;
  limit?: number;
};

export type EntitySearchFilters = {
  query: string;
  kind?: EntityKind;
  areaId?: number;
  limit?: number;
};

export type HueworksApi = {
  status(): Promise<unknown>;
  listAreas(): Promise<unknown>;
  area(areaId: number, includeDiagnostics?: boolean): Promise<unknown>;
  entity(kind: EntityKind, id: number, includeDiagnostics?: boolean): Promise<unknown>;
  searchEntities(filters: EntitySearchFilters): Promise<unknown>;
  controlTrace(filters?: TraceFilters): Promise<unknown>;
  activateScene(sceneId: number): Promise<unknown>;
  deactivateAreaScene(areaId: number): Promise<unknown>;
  controlEntity(kind: EntityKind, id: number, command: Record<string, unknown>): Promise<unknown>;
  refreshPhysicalState(): Promise<unknown>;
};

type HueworksApiClientOptions = {
  baseUrl: string;
  token: string;
  fetchImpl?: typeof fetch;
};

type HueworksApiErrorBody = {
  error?: {
    code?: unknown;
    message?: unknown;
    details?: unknown;
  };
};

export class HueworksApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = "HueworksApiError";
  }
}

export class HueworksApiClient implements HueworksApi {
  private readonly baseUrl: string;
  private readonly token: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: HueworksApiClientOptions) {
    const baseUrl = options.baseUrl.replace(/\/+$/, "");

    if (!/^https?:\/\//.test(baseUrl)) {
      throw new Error("HUEWORKS_API_URL must be an absolute http(s) URL.");
    }

    if (options.token.trim() === "") {
      throw new Error("HUEWORKS_API_TOKEN must not be empty.");
    }

    this.baseUrl = baseUrl;
    this.token = options.token;
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  static fromEnvironment(environment: NodeJS.ProcessEnv = process.env): HueworksApiClient {
    const baseUrl = environment.HUEWORKS_API_URL;
    const token = environment.HUEWORKS_API_TOKEN;

    if (!baseUrl) {
      throw new Error("HUEWORKS_API_URL is required.");
    }

    if (!token) {
      throw new Error("HUEWORKS_API_TOKEN is required.");
    }

    return new HueworksApiClient({ baseUrl, token });
  }

  get(path: string): Promise<unknown> {
    return this.request("GET", path);
  }

  status(): Promise<unknown> {
    return this.get("/api/v1/status");
  }

  listAreas(): Promise<unknown> {
    return this.get("/api/v1/areas");
  }

  area(areaId: number, includeDiagnostics = false): Promise<unknown> {
    const path = includeDiagnostics ? `/api/v1/debug/areas/${areaId}` : `/api/v1/areas/${areaId}`;
    return this.get(path);
  }

  entity(kind: EntityKind, id: number, includeDiagnostics = true): Promise<unknown> {
    const basePath = includeDiagnostics ? "/api/v1/debug" : "/api/v1";
    return this.get(`${basePath}/${kind}s/${id}`);
  }

  searchEntities(filters: EntitySearchFilters): Promise<unknown> {
    const parameters = new URLSearchParams();
    addParameter(parameters, "query", filters.query);
    addParameter(parameters, "kind", filters.kind);
    addParameter(parameters, "area_id", filters.areaId);
    addParameter(parameters, "limit", filters.limit);

    return this.get(`/api/v1/entities?${parameters.toString()}`);
  }

  controlTrace(filters: TraceFilters = {}): Promise<unknown> {
    const parameters = new URLSearchParams();
    addParameter(parameters, "trace_id", filters.traceId);
    addParameter(parameters, "area_id", filters.areaId);
    addParameter(parameters, "entity_kind", filters.entityKind);
    addParameter(parameters, "entity_id", filters.entityId);
    addParameter(parameters, "source", filters.source);
    addParameter(parameters, "limit", filters.limit);

    const query = parameters.toString();
    return this.get(`/api/v1/traces${query === "" ? "" : `?${query}`}`);
  }

  activateScene(sceneId: number): Promise<unknown> {
    return this.request("POST", `/api/v1/scenes/${sceneId}/activate`, {});
  }

  deactivateAreaScene(areaId: number): Promise<unknown> {
    return this.request("DELETE", `/api/v1/areas/${areaId}/active-scene`);
  }

  controlEntity(kind: EntityKind, id: number, command: Record<string, unknown>): Promise<unknown> {
    return this.request("POST", `/api/v1/${kind}s/${id}/control`, command);
  }

  refreshPhysicalState(): Promise<unknown> {
    return this.request("POST", "/api/v1/runtime/physical-state/refresh", {});
  }

  private async request(method: string, path: string, body?: unknown): Promise<unknown> {
    const headers: Record<string, string> = {
      accept: "application/json",
      authorization: `Bearer ${this.token}`,
    };

    let requestBody: string | undefined;

    if (body !== undefined) {
      headers["content-type"] = "application/json";
      requestBody = JSON.stringify(body);
    }

    let response: Response;

    try {
      response = await this.fetchImpl(new URL(path, `${this.baseUrl}/`), {
        method,
        headers,
        body: requestBody,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Network request failed.";
      throw new HueworksApiError(0, "network_error", message);
    }

    const payload = await responsePayload(response);

    if (!response.ok) {
      const error = payload as HueworksApiErrorBody;
      const code = typeof error.error?.code === "string" ? error.error.code : "request_failed";
      const message =
        typeof error.error?.message === "string" ? error.error.message : `HueWorks returned ${response.status}.`;

      throw new HueworksApiError(response.status, code, message, error.error?.details);
    }

    return payload;
  }
}

function addParameter(parameters: URLSearchParams, key: string, value: string | number | undefined): void {
  if (value !== undefined) {
    parameters.set(key, String(value));
  }
}

async function responsePayload(response: Response): Promise<unknown> {
  const body = await response.text();

  if (body === "") {
    return {};
  }

  try {
    return JSON.parse(body) as unknown;
  } catch {
    return { error: { code: "invalid_response", message: "HueWorks returned invalid JSON." } };
  }
}
