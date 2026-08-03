import {
  ApiError,
  assertOnlyKeys,
  fetchWithTimeout,
  isRecord,
  optionalString,
  readJSONBody,
  requiredInteger,
  requiredString,
} from "./http";
import type { Dependencies, Env } from "./types";

const STRIPE_API_URL = "https://api.stripe.com/v1";
const SESSION_ID_PATTERN = /^cs_(?:test|live)_[A-Za-z0-9]{10,240}$/;
const IDEMPOTENCY_KEY_PATTERN = /^[A-Za-z0-9._:-]{16,255}$/;

interface CheckoutInput {
  amountCents: number;
  need: {
    id: string;
    title: string;
    teacherName: string;
    schoolName: string | null;
    origin: "local" | "donorsChoose" | "sample";
    sourceName: string | null;
    sourceURL: string | null;
  };
  donor: { name: string | null; email: string | null };
  message: string | null;
}

export async function createCheckout(
  request: Request,
  env: Env,
  dependencies: Dependencies,
): Promise<Record<string, unknown>> {
  const secretKey = requireStripeSecret(env);
  const successURL = validateRedirectURL(env.STRIPE_SUCCESS_URL, "STRIPE_SUCCESS_URL", true);
  const cancelURL = validateRedirectURL(env.STRIPE_CANCEL_URL, "STRIPE_CANCEL_URL", false);
  const idempotencyKey = request.headers.get("Idempotency-Key")?.trim() ?? "";
  if (!IDEMPOTENCY_KEY_PATTERN.test(idempotencyKey)) {
    throw new ApiError(400, "invalid_idempotency_key", "Idempotency-Key must be 16 to 255 safe ASCII characters.");
  }

  const input = validateCheckoutInput(await readJSONBody(request, 12_288));
  if (input.need.origin === "sample" && !isTestModeSecret(secretKey)) {
    throw new ApiError(
      409,
      "sample_checkout_requires_test_mode",
      "Sample requests can only use Stripe test mode.",
    );
  }
  const form = new URLSearchParams();
  form.set("mode", "payment");
  form.set("submit_type", "donate");
  form.set("payment_method_types[0]", "card");
  form.set("success_url", successURL);
  form.set("cancel_url", cancelURL);
  form.set("client_reference_id", input.need.id);
  form.set("line_items[0][price_data][currency]", "usd");
  form.set("line_items[0][price_data][unit_amount]", String(input.amountCents));
  form.set("line_items[0][price_data][product_data][name]", `Classroom support: ${input.need.title}`.slice(0, 127));
  form.set("line_items[0][quantity]", "1");
  form.set("payment_intent_data[description]", `Classroom support for ${input.need.teacherName}`.slice(0, 500));
  setMetadata(form, "need_id", input.need.id);
  setMetadata(form, "need_title", input.need.title);
  setMetadata(form, "teacher_name", input.need.teacherName);
  if (input.need.schoolName) setMetadata(form, "school_name", input.need.schoolName);
  setMetadata(form, "need_origin", input.need.origin);
  if (input.need.sourceName) setMetadata(form, "source_name", input.need.sourceName);
  if (input.need.sourceURL) setMetadata(form, "source_url", input.need.sourceURL);
  if (input.donor.name) setMetadata(form, "donor_name", input.donor.name);
  if (input.message) setMetadata(form, "donor_message", input.message);
  if (input.donor.email) form.set("customer_email", input.donor.email);

  const response = await fetchWithTimeout(
    dependencies.fetch,
    `${STRIPE_API_URL}/checkout/sessions`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
        "Idempotency-Key": idempotencyKey,
      },
      body: form.toString(),
    },
    20_000,
  );
  const payload = await parseStripeResponse(response);
  const sessionId = typeof payload.id === "string" && SESSION_ID_PATTERN.test(payload.id) ? payload.id : null;
  const checkoutURL = safeStripeCheckoutURL(payload.url);
  if (!sessionId || !checkoutURL) {
    throw new ApiError(502, "invalid_provider_response", "The payment provider returned invalid checkout data.");
  }

  return {
    checkoutSessionId: sessionId,
    checkoutURL,
    expiresAt: unixTimestampToISO(payload.expires_at),
  };
}

export async function verifyCheckout(
  requestURL: URL,
  env: Env,
  dependencies: Dependencies,
): Promise<Record<string, unknown>> {
  const secretKey = requireStripeSecret(env);
  for (const key of requestURL.searchParams.keys()) {
    if (key !== "sessionId") throw new ApiError(400, "invalid_query", "The request contains an unsupported query parameter.");
  }
  const sessionId = requestURL.searchParams.get("sessionId")?.trim() ?? "";
  if (!SESSION_ID_PATTERN.test(sessionId)) {
    throw new ApiError(400, "invalid_session_id", "sessionId is not a valid Checkout Session ID.");
  }

  const response = await fetchWithTimeout(
    dependencies.fetch,
    `${STRIPE_API_URL}/checkout/sessions/${encodeURIComponent(sessionId)}`,
    { headers: { Authorization: `Bearer ${secretKey}` } },
    15_000,
  );
  const payload = await parseStripeResponse(response);
  if (payload.id !== sessionId) {
    throw new ApiError(502, "invalid_provider_response", "The payment provider returned mismatched session data.");
  }

  const paymentStatus = typeof payload.payment_status === "string" ? payload.payment_status : "unknown";
  return {
    checkoutSessionId: sessionId,
    paid: paymentStatus === "paid",
    paymentStatus,
    status: typeof payload.status === "string" ? payload.status : null,
    amountTotal: typeof payload.amount_total === "number" && Number.isInteger(payload.amount_total) ? payload.amount_total : null,
    currency: typeof payload.currency === "string" ? payload.currency : null,
    needId: isRecord(payload.metadata) && typeof payload.metadata.need_id === "string" ? payload.metadata.need_id : null,
  };
}

function validateCheckoutInput(body: Record<string, unknown>): CheckoutInput {
  assertOnlyKeys(body, ["amountCents", "currency", "need", "donor", "message"]);
  if (body.currency !== undefined && body.currency !== "usd") {
    throw new ApiError(400, "invalid_currency", "Only usd donations are supported.");
  }
  const amountCents = requiredInteger(body.amountCents, "amountCents", 100, 100_000);

  if (!isRecord(body.need)) throw new ApiError(400, "invalid_field", "need must be an object.");
  assertOnlyKeys(body.need, ["id", "title", "teacherName", "schoolName", "origin", "sourceName", "sourceURL"]);
  const rawOrigin = requiredString(body.need.origin, "need.origin", 1, 20);
  if (rawOrigin !== "local" && rawOrigin !== "donorsChoose" && rawOrigin !== "sample") {
    throw new ApiError(400, "invalid_field", "need.origin is not supported.");
  }
  const origin: CheckoutInput["need"]["origin"] = rawOrigin;
  const need = {
    id: requiredString(body.need.id, "need.id", 1, 80),
    title: requiredString(body.need.title, "need.title", 1, 120),
    teacherName: requiredString(body.need.teacherName, "need.teacherName", 1, 100),
    schoolName: optionalString(body.need.schoolName, "need.schoolName", 120),
    origin,
    sourceName: optionalString(body.need.sourceName, "need.sourceName", 50),
    sourceURL: validateNeedURL(body.need.sourceURL),
  };
  if (!/^[A-Za-z0-9._:-]{1,80}$/.test(need.id)) {
    throw new ApiError(400, "invalid_field", "need.id contains unsupported characters.");
  }

  let donor: CheckoutInput["donor"] = { name: null, email: null };
  if (body.donor !== undefined && body.donor !== null) {
    if (!isRecord(body.donor)) throw new ApiError(400, "invalid_field", "donor must be an object.");
    assertOnlyKeys(body.donor, ["name", "email"]);
    donor = {
      name: optionalString(body.donor.name, "donor.name", 100),
      email: validateEmail(body.donor.email),
    };
  }

  return {
    amountCents,
    need,
    donor,
    message: optionalString(body.message, "message", 500),
  };
}

function validateEmail(value: unknown): string | null {
  const email = optionalString(value, "donor.email", 254)?.toLowerCase() ?? null;
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new ApiError(400, "invalid_field", "donor.email is not a valid email address.");
  }
  return email;
}

function validateNeedURL(value: unknown): string | null {
  const string = optionalString(value, "need.sourceURL", 2_048);
  if (!string) return null;
  try {
    const url = new URL(string);
    if (url.protocol !== "https:") throw new Error("not HTTPS");
    return url.toString();
  } catch {
    throw new ApiError(400, "invalid_field", "need.sourceURL must be an HTTPS URL.");
  }
}

function validateRedirectURL(value: string | undefined, name: string, requiresSessionId: boolean): string {
  const raw = value?.trim();
  if (!raw) throw new ApiError(503, "integration_unavailable", "The payment integration is not configured.");
  try {
    const url = new URL(raw);
    const isLocalhost = url.protocol === "http:" && (url.hostname === "localhost" || url.hostname === "127.0.0.1");
    if (url.protocol !== "https:" && !isLocalhost) throw new Error("unsafe redirect");
    if (requiresSessionId && !raw.includes("{CHECKOUT_SESSION_ID}")) throw new Error("missing session placeholder");
    return raw;
  } catch {
    throw new ApiError(503, "invalid_configuration", `${name} is not configured correctly.`);
  }
}

function requireStripeSecret(env: Env): string {
  const secret = env.STRIPE_SECRET_KEY?.trim();
  if (!secret || !/^(?:sk|rk)_(?:test|live)_[A-Za-z0-9_]{10,}$/.test(secret)) {
    throw new ApiError(503, "integration_unavailable", "The payment integration is not configured.");
  }
  return secret;
}

function isTestModeSecret(secret: string): boolean {
  return /^(?:sk|rk)_test_/.test(secret);
}

function setMetadata(form: URLSearchParams, key: string, value: string): void {
  const bounded = value.slice(0, 500);
  form.set(`metadata[${key}]`, bounded);
  form.set(`payment_intent_data[metadata][${key}]`, bounded);
}

async function parseStripeResponse(response: Response): Promise<Record<string, unknown>> {
  let payload: unknown;
  try {
    payload = JSON.parse(await response.text());
  } catch {
    throw new ApiError(502, "invalid_provider_response", "The payment provider returned invalid data.");
  }
  if (!response.ok) {
    throw new ApiError(502, "provider_error", "The payment provider rejected the request.");
  }
  if (!isRecord(payload)) {
    throw new ApiError(502, "invalid_provider_response", "The payment provider returned invalid data.");
  }
  return payload;
}

function safeStripeCheckoutURL(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2_048) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && (url.hostname === "stripe.com" || url.hostname.endsWith(".stripe.com"))
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

function unixTimestampToISO(value: unknown): string | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? new Date(value * 1_000).toISOString()
    : null;
}
