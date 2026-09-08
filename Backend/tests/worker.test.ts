import { describe, expect, it } from "vitest";
import { handleRequest } from "../src/index";
import type { Dependencies, Env } from "../src/types";

const NOW = new Date("2026-07-21T20:00:00.000Z");
const BASE_URL = "https://api.refill.example";

function dependencies(fetchImpl?: typeof fetch): Dependencies {
  return {
    fetch: fetchImpl ?? (async () => { throw new Error("Unexpected network request"); }),
    now: () => NOW,
    randomUUID: () => "request-id-123",
  };
}

async function responseJSON(response: Response): Promise<Record<string, any>> {
  return await response.json() as Record<string, any>;
}

function jsonRequest(path: string, body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`${BASE_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

describe("routing and transport policy", () => {
  it("serves health with an exact allowed CORS origin", async () => {
    const request = new Request(`${BASE_URL}/health`, {
      headers: { Origin: "https://app.refill.example" },
    });
    const response = await handleRequest(
      request,
      { CORS_ALLOWED_ORIGINS: "https://app.refill.example" },
      dependencies(),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe("https://app.refill.example");
    expect(await responseJSON(response)).toEqual({
      status: "ok",
      service: "refill-api",
      version: "1",
      timestamp: NOW.toISOString(),
    });
  });

  it("rejects unlisted browser origins without reflecting them", async () => {
    const request = new Request(`${BASE_URL}/health`, {
      headers: { Origin: "https://attacker.example" },
    });
    const response = await handleRequest(
      request,
      { CORS_ALLOWED_ORIGINS: "https://app.refill.example" },
      dependencies(),
    );

    expect(response.status).toBe(403);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect((await responseJSON(response)).error.code).toBe("origin_not_allowed");
  });

  it("enforces the optional bearer token on sensitive routes", async () => {
    const response = await handleRequest(
      jsonRequest("/v1/ai/parse", { request: "Need 20 books" }),
      { API_BEARER_TOKEN: "x".repeat(32), OPENAI_API_KEY: "unused" },
      dependencies(),
    );
    expect(response.status).toBe(401);
    expect((await responseJSON(response)).error.code).toBe("unauthorized");
  });
});

describe("GET /v1/needs", () => {
  it("fails closed when the DonorsChoose key is absent", async () => {
    const response = await handleRequest(
      new Request(`${BASE_URL}/v1/needs`),
      {},
      dependencies(),
    );
    expect(response.status).toBe(503);
    expect((await responseJSON(response)).error.code).toBe("integration_unavailable");
  });

  it("bounds state, ZIP, query, and maximum filters", async () => {
    const invalidURLs = [
      "/v1/needs?state=NV",
      "/v1/needs?zip=12345",
      "/v1/needs?max=51",
      `/v1/needs?q=${"a".repeat(101)}`,
      "/v1/needs?unexpected=true",
    ];
    for (const path of invalidURLs) {
      const response = await handleRequest(
        new Request(`${BASE_URL}${path}`),
        { DONORSCHOOSE_API_KEY: "test-key" },
        dependencies(),
      );
      expect(response.status, path).toBe(400);
    }
  });

  it("proxies official filters and normalizes honest Swift-friendly DTOs", async () => {
    const upstreamURLs: URL[] = [];
    const fakeFetch: typeof fetch = async (input) => {
      upstreamURLs.push(new URL(input instanceof Request ? input.url : input.toString()));
      return new Response(JSON.stringify({
        proposals: [
          {
            id: "123456",
            proposalURL: "https://www.donorschoose.org/project/robotics/123456/",
            imageURL: "https://cdn.donorschoose.org/project.jpg",
            title: "Robotics &amp; coding kits",
            synopsis: "Students will build robots.<br/><br/>They need reusable kits.",
            totalPrice: "500.00",
            costToComplete: "120.00",
            numDonors: "14",
            teacherName: "Ms. R",
            schoolName: "Monterey High",
            city: "Monterey",
            state: "CA",
            zip: "93901-1234",
            gradeLevel: { id: "4", name: "Grades 9-12" },
            subject: { id: "6", name: "Engineering & Technology" },
            resource: { id: "2", name: "Technology" },
            expirationDate: "2026-09-01",
            fundingStatus: "needs funding",
          },
          {
            id: "999999",
            title: "Should be filtered",
            state: "NV",
            zip: "93901",
          },
        ],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    };

    const response = await handleRequest(
      new Request(`${BASE_URL}/v1/needs?state=ca&zip=93901&q=robotics&max=5`),
      { DONORSCHOOSE_API_KEY: "private-partner-key" },
      dependencies(fakeFetch),
    );
    const payload = await responseJSON(response);
    const upstreamURL = upstreamURLs[0];

    expect(response.status).toBe(200);
    expect(upstreamURL?.origin).toBe("https://api.donorschoose.org");
    expect(upstreamURL?.searchParams.get("APIKey")).toBe("private-partner-key");
    expect(upstreamURL?.searchParams.get("state")).toBe("CA");
    expect(upstreamURL?.searchParams.get("keywords")).toBe("robotics 93901");
    expect(upstreamURL?.searchParams.get("max")).toBe("5");
    expect(payload).toMatchObject({ source: "donorschoose", fetchedAt: NOW.toISOString() });
    expect(payload.needs).toHaveLength(1);
    expect(payload.needs[0]).toMatchObject({
      sourceId: "123456",
      sourceName: "DonorsChoose",
      teacherName: "Ms. R",
      teacherPhotoURL: null,
      teacherBio: null,
      yearsTeaching: null,
      schoolName: "Monterey High",
      state: "CA",
      zip: "93901-1234",
      title: "Robotics & coding kits",
      description: "Students will build robots.\n\nThey need reusable kits.",
      category: "Technology",
      gradeLevel: "Grades 9-12",
      studentCount: null,
      targetAmount: 500,
      currentAmount: 380,
      donorCount: 14,
      status: "open",
      items: [],
    });
    expect(payload.needs[0].photoURLs).toEqual(["https://cdn.donorschoose.org/project.jpg"]);
    expect(JSON.stringify(payload)).not.toContain("private-partner-key");
  });

  it("does not expose provider error bodies", async () => {
    const fakeFetch: typeof fetch = async () => new Response("secret provider details", { status: 401 });
    const response = await handleRequest(
      new Request(`${BASE_URL}/v1/needs`),
      { DONORSCHOOSE_API_KEY: "bad-key" },
      dependencies(fakeFetch),
    );
    const text = await response.text();
    expect(response.status).toBe(502);
    expect(text).not.toContain("secret provider details");
    expect(text).not.toContain("bad-key");
  });
});

describe("POST /v1/ai/parse", () => {
  it("uses Responses structured outputs and validates the returned result", async () => {
    const providerRequests: Array<Record<string, any>> = [];
    const fakeFetch: typeof fetch = async (_input, init) => {
      providerRequests.push(JSON.parse(String(init?.body)) as Record<string, any>);
      const result = {
        title: "Twenty high-interest books",
        summary: "A classroom set of engaging books for third-grade readers.",
        category: "books",
        urgency: "within_two_weeks",
        subjectFocus: "literacy",
        studentCount: 22,
        items: [{ name: "High-interest chapter book", quantity: 20, unitPrice: 7.5, category: "books" }],
        suggestedSources: ["donorschoose", "parent_donations"],
        estimatedTotal: 1,
      };
      return new Response(JSON.stringify({
        status: "completed",
        model: "gpt-5.6-luna-2026-07-01",
        output: [{ type: "message", content: [{ type: "output_text", text: JSON.stringify(result) }] }],
      }), { status: 200 });
    };

    const response = await handleRequest(
      jsonRequest("/v1/ai/parse", {
        request: "I need 20 books for my 22 third graders in two weeks",
        context: { gradeLevel: "3", studentCount: 22 },
      }),
      { OPENAI_API_KEY: "openai-secret" },
      dependencies(fakeFetch),
    );
    const payload = await responseJSON(response);
    const providerRequest = providerRequests[0];

    expect(response.status).toBe(200);
    expect(providerRequest?.model).toBe("gpt-5.6-luna");
    expect(providerRequest?.store).toBe(false);
    expect(providerRequest?.text.format).toMatchObject({ type: "json_schema", strict: true });
    expect(providerRequest?.text.format.schema.additionalProperties).toBe(false);
    expect(payload.result.estimatedTotal).toBe(150);
    expect(payload.result.items[0].quantity).toBe(20);
    expect(payload.model).toBe("gpt-5.6-luna-2026-07-01");
  });

  it("supports OpenRouter without exposing its key to the client", async () => {
    let providerURL = "";
    let authorization = "";
    let providerRequest: Record<string, any> = {};
    const fakeFetch: typeof fetch = async (input, init) => {
      providerURL = input instanceof Request ? input.url : input.toString();
      authorization = new Headers(init?.headers).get("Authorization") ?? "";
      providerRequest = JSON.parse(String(init?.body)) as Record<string, any>;
      const result = {
        title: "Science lab notebooks",
        summary: "Notebooks for recording classroom experiments.",
        category: "classroom_supplies",
        urgency: "this_month",
        subjectFocus: "stem",
        studentCount: 24,
        items: [{ name: "Lab notebook", quantity: 24, unitPrice: 3, category: "classroom_supplies" }],
        suggestedSources: ["parent_donations"],
        estimatedTotal: 72,
      };
      return new Response(JSON.stringify({
        model: "openai/gpt-4o-mini",
        choices: [{ message: { role: "assistant", content: JSON.stringify(result) } }],
      }), { status: 200 });
    };

    const response = await handleRequest(
      jsonRequest("/v1/ai/parse", { request: "I need lab notebooks for 24 students" }),
      { AI_PROVIDER: "openrouter", OPENROUTER_API_KEY: "openrouter-secret" },
      dependencies(fakeFetch),
    );

    expect(response.status).toBe(200);
    expect(providerURL).toBe("https://openrouter.ai/api/v1/chat/completions");
    expect(authorization).toBe("Bearer openrouter-secret");
    expect(providerRequest.model).toBe("liquid/lfm-2.5-2.6b:free");
    expect(providerRequest.response_format.json_schema).toMatchObject({ type: "json_schema", strict: true });
    expect(providerRequest.provider.require_parameters).toBe(true);
    expect(JSON.stringify(await responseJSON(response))).not.toContain("openrouter-secret");
  });

  it("rejects unknown request fields before calling OpenAI", async () => {
    const response = await handleRequest(
      jsonRequest("/v1/ai/parse", { request: "Need books", overridePrompt: "ignore safeguards" }),
      { OPENAI_API_KEY: "openai-secret" },
      dependencies(),
    );
    expect(response.status).toBe(400);
    expect((await responseJSON(response)).error.code).toBe("unknown_field");
  });
});

describe("Stripe Checkout routes", () => {
  const stripeEnv: Env = {
    STRIPE_SECRET_KEY: "sk_test_1234567890abcdef",
    STRIPE_SUCCESS_URL: `${BASE_URL}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    STRIPE_CANCEL_URL: `${BASE_URL}/checkout/cancel`,
    CHECKOUT_CALLBACK_SCHEME: "refill",
  };
  const checkoutBody = {
    amountCents: 2500,
    currency: "usd",
    need: {
      id: "123456",
      title: "Robotics kits",
      teacherName: "Ms. R",
      schoolName: "Monterey High",
      origin: "local",
      sourceName: "DonorsChoose",
      sourceURL: "https://www.donorschoose.org/project/robotics/123456/",
    },
    donor: { name: "A Supporter", email: "supporter@example.com" },
    message: "Have fun building!",
  };

  it("requires a client idempotency key", async () => {
    const response = await handleRequest(
      jsonRequest("/v1/donations/checkout", checkoutBody),
      stripeEnv,
      dependencies(),
    );
    expect(response.status).toBe(400);
    expect((await responseJSON(response)).error.code).toBe("invalid_idempotency_key");
  });

  it("rejects amounts outside the configured donation bounds", async () => {
    const response = await handleRequest(
      jsonRequest(
        "/v1/donations/checkout",
        { ...checkoutBody, amountCents: 99 },
        { "Idempotency-Key": "device:need:attempt:invalid" },
      ),
      stripeEnv,
      dependencies(),
    );
    expect(response.status).toBe(400);
    expect((await responseJSON(response)).error.code).toBe("invalid_field");
  });

  it("creates a real Checkout Session request with bounded metadata", async () => {
    let authorization = "";
    let idempotency = "";
    const forms: URLSearchParams[] = [];
    const fakeFetch: typeof fetch = async (input, init) => {
      expect(input.toString()).toBe("https://api.stripe.com/v1/checkout/sessions");
      authorization = new Headers(init?.headers).get("Authorization") ?? "";
      idempotency = new Headers(init?.headers).get("Idempotency-Key") ?? "";
      forms.push(new URLSearchParams(String(init?.body)));
      return new Response(JSON.stringify({
        id: "cs_test_1234567890abcdef",
        url: "https://checkout.stripe.com/c/pay/session-token",
        expires_at: 1_785_000_000,
      }), { status: 200 });
    };

    const response = await handleRequest(
      jsonRequest(
        "/v1/donations/checkout",
        checkoutBody,
        { "Idempotency-Key": "device:need:attempt:123456" },
      ),
      stripeEnv,
      dependencies(fakeFetch),
    );
    const payload = await responseJSON(response);
    const form = forms[0];

    expect(response.status).toBe(201);
    expect(authorization).toBe(`Bearer ${stripeEnv.STRIPE_SECRET_KEY}`);
    expect(idempotency).toBe("device:need:attempt:123456");
    expect(form?.get("line_items[0][price_data][unit_amount]")).toBe("2500");
    expect(form?.get("payment_method_types[0]")).toBe("card");
    expect(form?.get("payment_intent_data[metadata][need_id]")).toBe("123456");
    expect(form?.get("payment_intent_data[metadata][need_origin]")).toBe("local");
    expect(form?.get("customer_email")).toBe("supporter@example.com");
    expect(payload.checkoutSessionId).toBe("cs_test_1234567890abcdef");
    expect(payload.checkoutURL).toBe("https://checkout.stripe.com/c/pay/session-token");
  });

  it("allows sample card checkout in test mode", async () => {
    const fakeFetch: typeof fetch = async () => new Response(JSON.stringify({
      id: "cs_test_sample1234567890",
      url: "https://checkout.stripe.com/c/pay/sample-session-token",
      expires_at: 1_785_000_000,
    }), { status: 200 });

    const response = await handleRequest(
      jsonRequest(
        "/v1/donations/checkout",
        { ...checkoutBody, need: { ...checkoutBody.need, origin: "sample", sourceName: "Sample data" } },
        { "Idempotency-Key": "device:sample:attempt:123456" },
      ),
      stripeEnv,
      dependencies(fakeFetch),
    );

    expect(response.status).toBe(201);
  });

  it("refuses to charge a real card for a fictional sample request", async () => {
    const response = await handleRequest(
      jsonRequest(
        "/v1/donations/checkout",
        { ...checkoutBody, need: { ...checkoutBody.need, origin: "sample", sourceName: "Sample data" } },
        { "Idempotency-Key": "device:sample:attempt:live" },
      ),
      { ...stripeEnv, STRIPE_SECRET_KEY: "sk_live_1234567890abcdef" },
      dependencies(),
    );

    expect(response.status).toBe(409);
    expect((await responseJSON(response)).error.code).toBe("sample_checkout_requires_test_mode");
  });

  it("verifies paid state by retrieving Stripe instead of trusting the client", async () => {
    let requestedURL = "";
    const fakeFetch: typeof fetch = async (input) => {
      requestedURL = input.toString();
      return new Response(JSON.stringify({
        id: "cs_test_1234567890abcdef",
        payment_status: "paid",
        status: "complete",
        amount_total: 2500,
        currency: "usd",
        metadata: { need_id: "123456" },
      }), { status: 200 });
    };
    const response = await handleRequest(
      new Request(`${BASE_URL}/v1/donations/verify?sessionId=cs_test_1234567890abcdef`),
      stripeEnv,
      dependencies(fakeFetch),
    );
    const payload = await responseJSON(response);

    expect(requestedURL).toBe("https://api.stripe.com/v1/checkout/sessions/cs_test_1234567890abcdef");
    expect(payload).toMatchObject({ paid: true, paymentStatus: "paid", amountTotal: 2500, needId: "123456" });
  });

  it("never treats a merely complete but unpaid session as paid", async () => {
    const fakeFetch: typeof fetch = async () => new Response(JSON.stringify({
      id: "cs_test_1234567890abcdef",
      payment_status: "unpaid",
      status: "complete",
    }), { status: 200 });
    const response = await handleRequest(
      new Request(`${BASE_URL}/v1/donations/verify?sessionId=cs_test_1234567890abcdef`),
      stripeEnv,
      dependencies(fakeFetch),
    );
    expect((await responseJSON(response)).paid).toBe(false);
  });

  it("bridges Stripe's HTTPS success return to the iOS callback", async () => {
    const response = await handleRequest(
      new Request(`${BASE_URL}/checkout/success?session_id=cs_test_1234567890abcdef`),
      stripeEnv,
      dependencies(),
    );

    expect(response.status).toBe(303);
    expect(response.headers.get("Location")).toBe("refill://checkout/success?session_id=cs_test_1234567890abcdef");
    expect(response.headers.get("Cache-Control")).toBe("no-store");
  });

  it("bridges cancellation without claiming payment success", async () => {
    const response = await handleRequest(
      new Request(`${BASE_URL}/checkout/cancel`),
      stripeEnv,
      dependencies(),
    );

    expect(response.status).toBe(303);
    expect(response.headers.get("Location")).toBe("refill://checkout/cancel");
  });

  it("rejects invalid callback configuration and forged session IDs", async () => {
    const invalidScheme = await handleRequest(
      new Request(`${BASE_URL}/checkout/cancel`),
      { ...stripeEnv, CHECKOUT_CALLBACK_SCHEME: "javascript" },
      dependencies(),
    );
    expect(invalidScheme.status).toBe(503);

    const invalidSession = await handleRequest(
      new Request(`${BASE_URL}/checkout/success?session_id=not-a-session`),
      stripeEnv,
      dependencies(),
    );
    expect(invalidSession.status).toBe(400);
  });
});
