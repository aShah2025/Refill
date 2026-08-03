import { ApiError } from "./http";
import type { Env } from "./types";

const SESSION_ID_PATTERN = /^cs_(?:test|live)_[A-Za-z0-9]{10,240}$/;
const SCHEME_PATTERN = /^[a-z][a-z0-9+.-]{1,63}$/;
const RESERVED_SCHEMES = new Set(["data", "file", "http", "https", "javascript"]);

/**
 * Bridges Stripe's required HTTPS return URL back into the active iOS
 * ASWebAuthenticationSession. Payment state is still verified independently
 * against Stripe after this redirect, so callback parameters are never proof
 * of payment.
 */
export function checkoutCallback(
  requestURL: URL,
  env: Env,
  outcome: "success" | "cancel",
): Response {
  const scheme = callbackScheme(env);
  const allowedKeys = outcome === "success" ? new Set(["session_id"]) : new Set<string>();
  for (const key of requestURL.searchParams.keys()) {
    if (!allowedKeys.has(key)) {
      throw new ApiError(400, "invalid_query", "The checkout return URL contains an unsupported parameter.");
    }
  }

  const callbackURL = new URL(`${scheme}://checkout/${outcome}`);
  if (outcome === "success") {
    const sessionId = requestURL.searchParams.get("session_id")?.trim() ?? "";
    if (!SESSION_ID_PATTERN.test(sessionId)) {
      throw new ApiError(400, "invalid_session_id", "The checkout return URL is missing a valid session ID.");
    }
    callbackURL.searchParams.set("session_id", sessionId);
  }

  return new Response(null, {
    status: 303,
    headers: {
      Location: callbackURL.toString(),
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function callbackScheme(env: Env): string {
  const scheme = env.CHECKOUT_CALLBACK_SCHEME?.trim().toLowerCase() ?? "";
  if (!SCHEME_PATTERN.test(scheme) || RESERVED_SCHEMES.has(scheme)) {
    throw new ApiError(503, "invalid_configuration", "The checkout callback is not configured correctly.");
  }
  return scheme;
}
