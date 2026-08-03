import { getNeeds } from "./donorschoose";
import {
  ApiError,
  corsHeadersFor,
  errorResponse,
  jsonResponse,
  requireBearerIfConfigured,
} from "./http";
import { parseClassroomRequest } from "./openai";
import { createCheckout, verifyCheckout } from "./stripe";
import { checkoutCallback } from "./checkout-callback";
import type { Dependencies, Env } from "./types";

const defaultDependencies: Dependencies = {
  fetch: globalThis.fetch.bind(globalThis),
  now: () => new Date(),
  randomUUID: () => crypto.randomUUID(),
};

export async function handleRequest(
  request: Request,
  env: Env,
  dependencies: Dependencies = defaultDependencies,
): Promise<Response> {
  const cfRay = request.headers.get("CF-Ray") ?? "";
  const requestId = /^[A-Za-z0-9:.-]{1,128}$/.test(cfRay) ? cfRay : dependencies.randomUUID();
  let corsHeaders: Record<string, string> = {};

  try {
    corsHeaders = corsHeadersFor(request, env);
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (url.pathname === "/health") {
      assertMethod(request, "GET");
      return jsonResponse(
        { status: "ok", service: "refill-api", version: "1", timestamp: dependencies.now().toISOString() },
        200,
        { ...corsHeaders, "Cache-Control": "no-store" },
      );
    }

    if (url.pathname === "/v1/needs") {
      assertMethod(request, "GET");
      const result = await getNeeds(url, env, dependencies);
      return jsonResponse(result, 200, {
        ...corsHeaders,
        "Cache-Control": "public, max-age=300, stale-while-revalidate=600",
      });
    }

    if (url.pathname === "/v1/ai/parse") {
      assertMethod(request, "POST");
      await requireBearerIfConfigured(request, env);
      return jsonResponse(await parseClassroomRequest(request, env, dependencies), 200, {
        ...corsHeaders,
        "Cache-Control": "no-store",
      });
    }

    if (url.pathname === "/v1/donations/checkout") {
      assertMethod(request, "POST");
      await requireBearerIfConfigured(request, env);
      return jsonResponse(await createCheckout(request, env, dependencies), 201, {
        ...corsHeaders,
        "Cache-Control": "no-store",
      });
    }

    if (url.pathname === "/v1/donations/verify") {
      assertMethod(request, "GET");
      await requireBearerIfConfigured(request, env);
      return jsonResponse(await verifyCheckout(url, env, dependencies), 200, {
        ...corsHeaders,
        "Cache-Control": "no-store",
      });
    }

    if (url.pathname === "/checkout/success") {
      assertMethod(request, "GET");
      return checkoutCallback(url, env, "success");
    }

    if (url.pathname === "/checkout/cancel") {
      assertMethod(request, "GET");
      return checkoutCallback(url, env, "cancel");
    }

    throw new ApiError(404, "not_found", "The requested endpoint does not exist.");
  } catch (error) {
    return errorResponse(error, requestId, corsHeaders);
  }
}

function assertMethod(request: Request, expected: "GET" | "POST"): void {
  if (request.method !== expected) {
    throw new ApiError(405, "method_not_allowed", `This endpoint requires ${expected}.`);
  }
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
} satisfies ExportedHandler<Env>;
