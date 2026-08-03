import type { Env } from "./types";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
    this.name = "ApiError";
  }
}

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...Object.fromEntries(new Headers(extraHeaders)) },
  });
}

export function errorResponse(
  error: unknown,
  requestId: string,
  corsHeaders: HeadersInit = {},
): Response {
  const apiError = error instanceof ApiError
    ? error
    : new ApiError(500, "internal_error", "The request could not be completed.");

  return jsonResponse(
    {
      error: {
        code: apiError.code,
        message: apiError.publicMessage,
      },
      requestId,
    },
    apiError.status,
    { ...Object.fromEntries(new Headers(corsHeaders)), "Cache-Control": "no-store" },
  );
}

export function corsHeadersFor(request: Request, env: Env): Record<string, string> {
  const origin = request.headers.get("Origin");
  if (!origin) return { Vary: "Origin" };

  const allowed = new Set(
    (env.CORS_ALLOWED_ORIGINS ?? "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean),
  );

  if (!allowed.has(origin)) {
    throw new ApiError(403, "origin_not_allowed", "This browser origin is not allowed.");
  }

  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type, Idempotency-Key",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

export async function requireBearerIfConfigured(request: Request, env: Env): Promise<void> {
  const expected = env.API_BEARER_TOKEN?.trim();
  if (!expected) return;
  if (expected.length < 32 || expected.length > 512) {
    throw new ApiError(503, "invalid_configuration", "API authorization is not configured correctly.");
  }

  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match || !(await constantTimeEqual(match[1] ?? "", expected))) {
    throw new ApiError(401, "unauthorized", "Valid authorization is required.");
  }
}

async function constantTimeEqual(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [leftHash, rightHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const a = new Uint8Array(leftHash);
  const b = new Uint8Array(rightHash);
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index += 1) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

export async function readJSONBody(
  request: Request,
  maxBytes: number,
): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("Content-Type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) {
    throw new ApiError(415, "unsupported_media_type", "Content-Type must be application/json.");
  }

  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new ApiError(413, "request_too_large", "The request body is too large.");
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    throw new ApiError(413, "request_too_large", "The request body is too large.");
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new ApiError(400, "invalid_json", "The request body is not valid JSON.");
  }
  if (!isRecord(value)) {
    throw new ApiError(400, "invalid_body", "The request body must be a JSON object.");
  }
  return value;
}

export async function fetchWithTimeout(
  fetchImpl: typeof globalThis.fetch,
  input: RequestInfo | URL,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(input, { ...init, signal: controller.signal });
  } catch (error) {
    if (controller.signal.aborted) {
      throw new ApiError(504, "upstream_timeout", "An upstream service timed out.");
    }
    throw new ApiError(502, "upstream_unavailable", "An upstream service is unavailable.");
  } finally {
    clearTimeout(timeout);
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function assertOnlyKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
): void {
  const allowedSet = new Set(allowed);
  if (Object.keys(value).some((key) => !allowedSet.has(key))) {
    throw new ApiError(400, "unknown_field", "The request contains an unsupported field.");
  }
}

export function requiredString(
  value: unknown,
  field: string,
  minLength: number,
  maxLength: number,
): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "invalid_field", `${field} must be a string.`);
  }
  const normalized = value.trim();
  if (normalized.length < minLength || normalized.length > maxLength || /[\u0000-\u001F\u007F]/u.test(normalized)) {
    throw new ApiError(400, "invalid_field", `${field} has an invalid length or characters.`);
  }
  return normalized;
}

export function optionalString(
  value: unknown,
  field: string,
  maxLength: number,
): string | null {
  if (value === undefined || value === null || value === "") return null;
  return requiredString(value, field, 1, maxLength);
}

export function requiredInteger(
  value: unknown,
  field: string,
  min: number,
  max: number,
): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    throw new ApiError(400, "invalid_field", `${field} must be an integer from ${min} through ${max}.`);
  }
  return value;
}
