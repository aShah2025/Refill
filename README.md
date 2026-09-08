# Refill

Refill is a SwiftUI iOS 17+ prototype for drafting classroom supply requests and helping supporters discover projects. It has a real server integration boundary, but a default checkout build is **not** a production fundraising system: live data and AI require approved provider credentials, user/account sync is still local-only, and Stripe does not automatically deliver money to DonorsChoose or a classroom.

## What is live, and what is a fallback

| Capability | With the required configuration | Without it |
| --- | --- | --- |
| Classroom projects | The iOS app calls the Cloudflare Worker, which normalizes current California DonorsChoose listings. Successful results are cached on device for 24 hours. | A valid cache is used first; otherwise bundled projects appear with a **Sample data** label. |
| School directory | The app reads public NCES school reference data from the Urban Institute Education Data Portal for four counties associated with CA-19. | School lookup reports that the directory is unavailable; it never turns school records into classroom requests. |
| Request parsing | The Worker calls the configured OpenRouter or OpenAI Responses API with a strict JSON schema and returns the model name used. | The app uses a deterministic on-device parser and labels that result as a fallback. Funding-route suggestions remain local heuristics and are not provider eligibility decisions. |
| Donations | DonorsChoose projects open their official provider page. A locally created open need can use Stripe-hosted Checkout; the app records a receipt only after the Worker retrieves the session from Stripe and verifies `payment_status=paid`, amount, currency, and need ID. Configured sample projects can exercise the same flow only with Stripe test-mode credentials. | Sample projects offer an on-device card sandbox that accepts only `4242 4242 4242 4242`, never transmits card input, and creates a test-only activity entry. Real checkout remains disabled without backend configuration. |

The DonorsChoose feed currently defaults to California-wide results (20 projects), not an exact congressional-district boundary. The school directory's county set is also not district geofencing. Provider fields that DonorsChoose does not supply—such as teacher biographies, headshots, years teaching, and student counts—must not be presented as verified data.

Teacher-created requests, favorites, notifications, and verified receipt summaries are stored in `UserDefaults` on the current device. There is no account authentication, multi-device sync, remote publishing, server-side request database, or push-notification service yet.

## Architecture

- `Refill/` contains the SwiftUI app, local state, the 24-hour classroom-needs cache, a direct read-only school-directory client, and clients for the Worker routes.
- `Backend/` contains a Cloudflare Worker with `GET /v1/needs`, `POST /v1/ai/parse`, `POST /v1/donations/checkout`, `GET /v1/donations/verify`, and narrow `/checkout/success` and `/checkout/cancel` app-return bridges.
- Only the Worker calls provider APIs or holds provider credentials; the app may open provider-hosted pages. Secrets must never be added to the app, an Info.plist, source control, or a mobile build.

See [Backend/README.md](Backend/README.md) for request/response contracts and route-level controls.

## Prerequisites

- A current Xcode version that can open this project and an iOS 17+ Simulator or device.
- Node.js 20+ and a Cloudflare account for the Worker.
- An approved DonorsChoose API key. [DonorsChoose currently limits integrations to qualifying partners](https://www.donorschoose.org/api/docs/overview/); the listing endpoint is not an anonymous public feed.
- An OpenRouter API key with access to the configured model, or an OpenAI API project/key. OpenRouter is the default and uses `OPENROUTER_MODEL=openai/gpt-4o-mini`; both providers use strict structured output.
- A Stripe account and test-mode secret key for checkout testing. Live payments additionally require a decided merchant/recipient model, disbursement and refund operations, tax-receipt policy, webhook reconciliation, and legal review.

## Run the Worker locally

```sh
cd Backend
npm install
cp .dev.vars.example .dev.vars
```

Replace the placeholders in `.dev.vars`, then run:

```sh
npm run check
npm run dev
curl http://localhost:8787/health
```

Use Stripe test credentials and test payment methods during development. Sample requests deliberately reject live-mode Stripe keys, but they open the complete Stripe-hosted card form when the Worker uses a test key. Point `STRIPE_SUCCESS_URL` and `STRIPE_CANCEL_URL` to this Worker's `/checkout/success` and `/checkout/cancel` routes; the success URL must include the literal `{CHECKOUT_SESSION_ID}` placeholder. Set Worker secret `CHECKOUT_CALLBACK_SCHEME` to the same value as iOS `REFILL_CHECKOUT_CALLBACK_SCHEME`. The Worker then returns the active browser session to `refill://checkout/success` or `refill://checkout/cancel`; the callback itself is never treated as proof of payment.

With no Worker configuration, tapping a sample request's **Donate** button opens the built-in credit/debit-card sheet immediately. It accepts only `4242 4242 4242 4242`, any future `MM/YY`, and any three-digit CVC. The sandbox is a local UI simulation—not a Stripe payment—and its input is neither stored nor transmitted.

`API_BEARER_TOKEN` is optional on the Worker. The current iOS client does not attach it, so setting it will intentionally make AI and checkout calls return `401`. Do not solve this by embedding a shared production token in the app; implement user-scoped authentication or a short-lived token exchange before public release.

## Configure and run iOS

Open `Refill.xcworkspace`, select the `Refill` scheme, and configure these Run environment variables under **Product → Scheme → Edit Scheme → Run → Arguments**:

| Name | Development value |
| --- | --- |
| `REFILL_BACKEND_BASE_URL` | `http://localhost:8787` for Simulator, or the deployed HTTPS Worker URL |
| `REFILL_CHECKOUT_CALLBACK_SCHEME` | `refill` (the scheme registered by the included Debug and Release configurations) |

Do not append `/v1` to the base URL. Non-HTTPS remote URLs, URLs containing credentials/query/fragment, and unresolved build-setting placeholders are rejected. A physical device cannot reach the Mac through its own `localhost`; use the deployed HTTPS Worker.

The included `Refill/Info.plist` registers the callback through the `REFILL_CHECKOUT_CALLBACK_SCHEME` build setting, which currently resolves to `refill`. If that value changes, update the build setting and the Worker's `CHECKOUT_CALLBACK_SCHEME` together; changing only a Run environment variable does not register a new URL scheme. For archived builds, expose the backend URL through per-configuration build settings or an uncommitted `.xcconfig`. Never put provider API keys there.

Run from Xcode, or verify a simulator build from the repository root:

```sh
xcodebuild -project Refill.xcodeproj \
  -scheme Refill \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the hermetic iOS service tests on an available simulator:

```sh
xcodebuild -project Refill.xcodeproj \
  -scheme Refill \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

`RefillTests` covers stable identifiers, deterministic parsing, fixture provenance, configuration validation, bounded networking, and verified/cancelled checkout flows. `npm run check` type-checks the Worker and runs mocked provider tests without contacting live accounts. There is not yet an automated iOS UI-test target; use a Stripe test-mode end-to-end checkout as a separate manual smoke test.

## Deploy the Worker

From `Backend/`, authenticate Wrangler, set secrets, and deploy:

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
npm run deploy
```

`AI_PROVIDER`, `OPENROUTER_MODEL`, `OPENAI_MODEL`, and `CORS_ALLOWED_ORIGINS` are ordinary Worker variables in `wrangler.toml`; set exact browser origins for production. Native iOS requests normally have no `Origin`, and CORS is not authentication. Cloudflare's current guidance for secrets and deployment is in the [Workers secrets documentation](https://developers.cloudflare.com/workers/configuration/secrets/) and [Wrangler command reference](https://developers.cloudflare.com/workers/wrangler/commands/workers/).

## Privacy, security, and payment caveats

- Onboarding currently stores name, email, coarse location/school details, classroom content, and local activity in `UserDefaults`; this is app-local persistence, not a secure account store. Minimize data and do not enter student-identifying information.
- When live AI is enabled, the classroom request and selected context are sent through the Worker to the configured AI provider with `store: false`. Publish an accurate provider-specific privacy/retention notice and review under-18 requirements before launch.
- Stripe receives the amount, project metadata, and any donor email/message supplied. The Stripe account configured by `STRIPE_SECRET_KEY` is the merchant receiving funds.
- Sample requests are fictional. Their configured Stripe checkout sessions are restricted to test mode; without Stripe configuration, they use an on-device sandbox. Both paths appear as test receipts and do not count toward real impact totals or classroom funding.
- A Stripe payment is **not** a DonorsChoose donation and does not update DonorsChoose funding totals. Prefer the official DonorsChoose funding link unless Refill has an approved collection and disbursement model; DonorsChoose transactional API access requires separate approval.
- Add real user authorization, abuse controls/rate limits, Stripe webhooks, reconciliation, observability with redaction, provider-term review, and deletion/export controls before a public production launch.
