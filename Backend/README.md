# Refill Cloudflare Worker

This directory contains the server-side integration boundary for Refill. It uses the Cloudflare Workers `fetch` runtime directly—there are no OpenRouter, OpenAI, Stripe, or DonorsChoose runtime SDK dependencies.

The Worker never returns sample needs, fake AI results, fake Checkout Sessions, or fake payment success. Missing credentials and provider failures produce explicit non-2xx responses.

## Routes

### `GET /health`

Returns a small liveness response and does not disclose which provider credentials are configured.

### `GET /v1/needs`

Proxies the official DonorsChoose project-listing API and returns:

```json
{
  "needs": [],
  "source": "donorschoose",
  "fetchedAt": "2026-07-21T20:00:00.000Z"
}
```

Supported query parameters are deliberately bounded:

- `state`: optional, but only `CA` is accepted.
- `zip`: optional five-digit California ZIP (`90001` through `96162`).
- `q`: optional keyword query, at most 100 characters.
- `max`: optional integer from 1 through 50; defaults to 20.

Every normalized need uses camelCase fields: `sourceId`, `sourceName`, `sourceURL`, `teacherName`, `teacherPhotoURL`, `teacherBio`, `yearsTeaching`, `schoolName`, `city`, `state`, `zip`, `schoolType`, `title`, `description`, `category`, `gradeLevel`, `studentCount`, `items`, `targetAmount`, `currentAmount`, `donorCount`, `createdAt`, `deadline`, `photoURLs`, and `status`.

The DonorsChoose listing API does not provide a teacher headshot, biography, years teaching, or student count. Those values are returned as `null`, not invented. Its `imageURL` is a project/classroom image and is therefore placed in `photoURLs`. Documentation: [project listing requests](https://www.donorschoose.org/api/docs/project-listing/json-requests/) and [responses](https://www.donorschoose.org/api/docs/project-listing/json-responses/).

DonorsChoose currently provisions API access through partner relationships; obtain approval and a key before enabling this route. The key remains on the Worker.

### `POST /v1/ai/parse`

Calls the OpenRouter or OpenAI Responses API with strict JSON Schema Structured Outputs. OpenRouter is the default (`AI_PROVIDER=openrouter`) and `OPENROUTER_MODEL` defaults to the zero-cost `openrouter/free` router. The free router selects an available model that supports the request's required features, but has lower rate limits and variable availability. Set `AI_PROVIDER=openai` to use `OPENAI_API_KEY` and `OPENAI_MODEL` instead. The provider key remains on the Worker.

Request:

```json
{
  "request": "I need 20 books for my 22 third graders within two weeks",
  "context": {
    "gradeLevel": "3",
    "subject": "Literacy",
    "studentCount": 22,
    "urgency": "within two weeks"
  }
}
```

Response:

```json
{
  "result": {
    "title": "Twenty high-interest books",
    "summary": "A classroom set for third-grade readers.",
    "category": "books",
    "urgency": "within_two_weeks",
    "subjectFocus": "literacy",
    "studentCount": 22,
    "items": [
      { "name": "High-interest chapter book", "quantity": 20, "unitPrice": 7.5, "category": "books" }
    ],
    "suggestedSources": ["donorschoose", "parent_donations"],
    "estimatedTotal": 150
  },
  "model": "gpt-5.6-luna"
}
```

The Worker validates the provider result again and recomputes `estimatedTotal` from item quantities and unit-price estimates. See [OpenRouter Responses](https://openrouter.ai/docs/api/api-reference/responses/create-responses), [OpenRouter structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs), or [OpenAI Responses](https://platform.openai.com/docs/api-reference/responses).

### `POST /v1/donations/checkout`

Creates a one-time Stripe Checkout Session. A unique `Idempotency-Key` header (16–255 safe ASCII characters) is mandatory.

```json
{
  "amountCents": 2500,
  "currency": "usd",
  "need": {
    "id": "123456",
    "title": "Robotics kits",
    "teacherName": "Ms. R",
    "schoolName": "Monterey High",
    "origin": "local",
    "sourceName": "DonorsChoose",
    "sourceURL": "https://www.donorschoose.org/project/robotics/123456/"
  },
  "donor": {
    "name": "A Supporter",
    "email": "supporter@example.com"
  },
  "message": "Have fun building!"
}
```

`amountCents` is limited to $1–$1,000 and currency is fixed to USD. Checkout explicitly enables Stripe's card payment form. Redirect URLs come only from Worker configuration, never from the client. The response contains `checkoutSessionId`, Stripe-hosted `checkoutURL`, and `expiresAt`.

Sample requests (`need.origin == "sample"`) may create Checkout Sessions only when `STRIPE_SECRET_KEY` is a Stripe test-mode key. A live-mode key returns `409 sample_checkout_requires_test_mode`, preventing a real card charge for a fictional request while still allowing end-to-end card-entry testing.

For the included iOS return flow, point Stripe's server-controlled URLs back
to the deployed Worker and use the same custom scheme as the app:

```text
STRIPE_SUCCESS_URL=https://YOUR_WORKER/checkout/success?session_id={CHECKOUT_SESSION_ID}
STRIPE_CANCEL_URL=https://YOUR_WORKER/checkout/cancel
CHECKOUT_CALLBACK_SCHEME=refill
```

`GET /checkout/success` and `GET /checkout/cancel` are narrow HTTPS-to-app
bridges. They never mark a payment paid. The iOS client still calls the verify
endpoint and checks Stripe's paid status, session, amount, currency, and need ID
before creating a local receipt.

### `GET /v1/donations/verify?sessionId=cs_...`

Retrieves the Checkout Session from Stripe. `paid` is true only when Stripe returns `payment_status == "paid"`; client state and redirect parameters are never trusted.

Stripe Checkout collects money into the Stripe account configured by `STRIPE_SECRET_KEY`. It does **not** automatically transfer money to DonorsChoose or a classroom. Before accepting production payments, establish the legal recipient, disbursement, refund, tax-receipt, accounting, and webhook reconciliation process. If Refill is only referring users to DonorsChoose, use each need's official `sourceURL`/funding link instead of charging through Stripe.

## Local setup

Requirements: Node.js 20+ and a Cloudflare account for deployment.

```sh
cd Backend
npm install
cp .dev.vars.example .dev.vars
```

Replace placeholders in `.dev.vars`; that file is ignored by Git. Then run:

```sh
npm run dev
```

Example health check:

```sh
curl http://localhost:8787/health
```

Example authenticated AI request when `API_BEARER_TOKEN` is configured:

```sh
curl -X POST http://localhost:8787/v1/ai/parse \
  -H 'Authorization: Bearer replace-with-local-token' \
  -H 'Content-Type: application/json' \
  --data '{"request":"I need 20 books for third graders within two weeks"}'
```

## Tests and type checking

Tests mock all upstream HTTP calls. They never require or contact live provider accounts.

```sh
npm run check
```

The suite covers CORS, authentication, bounded filters, DonorsChoose normalization, safe provider errors, OpenRouter/OpenAI strict-schema payloads and response validation, Stripe idempotency, Checkout form creation, and paid/unpaid verification.

## Deploy

Authenticate Wrangler and set secrets; do not put them in `wrangler.toml`:

```sh
npx wrangler login
npx wrangler secret put DONORSCHOOSE_API_KEY
npx wrangler secret put OPENROUTER_API_KEY
# Optional alternative when AI_PROVIDER=openai:
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put STRIPE_SECRET_KEY
npx wrangler secret put STRIPE_SUCCESS_URL
npx wrangler secret put STRIPE_CANCEL_URL
npx wrangler secret put CHECKOUT_CALLBACK_SCHEME
npx wrangler secret put API_BEARER_TOKEN
npm run deploy
```

Set `CORS_ALLOWED_ORIGINS` in `wrangler.toml` or the Cloudflare dashboard to exact production web origins. Native iOS requests normally omit `Origin`; CORS is not authentication.

## Production security checklist

- Keep every provider key in Worker secrets and rotate immediately if exposed.
- Set `API_BEARER_TOKEN` for defense in depth. A token embedded in a mobile binary is extractable, so replace this with user-scoped authentication or Cloudflare Access before a public launch.
- Add a Cloudflare rate-limiting rule for `/v1/ai/*` and `/v1/donations/*`; CORS alone cannot prevent direct API abuse.
- Restrict browser origins to exact HTTPS origins. Do not use `*` for sensitive routes.
- Use a Stripe restricted key where possible, test mode before live mode, and a webhook for durable fulfillment/reconciliation. Redirect verification alone is not a webhook substitute.
- Keep success and cancellation URLs under an HTTPS domain you control. The included app expects the Worker bridge paths shown above; the success URL must contain `{CHECKOUT_SESSION_ID}`, and the callback scheme must match the iOS build setting.
- Do not log authorization headers, provider responses, donor messages, or API URLs containing the DonorsChoose key.
- Tell users that classroom request text is sent to the configured AI provider, minimize personal data, and apply the privacy/retention policy appropriate for the deployment.
- Review DonorsChoose data-display, referral, privacy, and transactional terms before production use.
