# Refill Product Requirements

Status: implementation baseline and production-readiness plan, 2026-07-22.

## Product intent

Refill helps teachers turn a plain-language classroom need into an editable request and helps supporters find transparent ways to fund or share it. The initial geographic focus is California's 19th Congressional District, but the product must never imply that state-wide or county-level data is exact district coverage.

Refill is not yet a production donation marketplace. The current app is a functional iOS prototype with conditional live integrations and explicit local/sample fallbacks.

## Users and core jobs

- Teachers draft, review, save, share, and close classroom requests; they receive suggested funding routes that they must verify with each provider.
- Parents and community supporters browse, search, filter, save, share, and open an official provider link or an approved checkout flow.
- Operators configure provider access, protect secrets, monitor failures and costs, reconcile payments, and maintain data/privacy compliance.

## Current implementation baseline

| Area | Current behavior | Production status |
| --- | --- | --- |
| Onboarding and profile | Role-specific onboarding and settings persist on one device in `UserDefaults`. | Prototype; no identity verification, secure account store, sync, export, or remote deletion. |
| Community feed | Configured builds load normalized DonorsChoose projects through the Worker, retain a 24-hour cache, and visibly identify source. An outage uses valid cache, then bundled sample records. | Conditional live. DonorsChoose approval/key required. Default feed is California-wide, not exact CA-19. |
| School lookup | Reads public NCES reference data from the Urban Institute for four counties and validates the returned county codes. | Live reference data, not classroom needs and not district-boundary proof. |
| Teacher request creation | Teachers review parsed items, totals, category, urgency, and summary before saving a local request. | Functional locally; requests are not published to a shared backend or DonorsChoose. |
| AI parsing | Optional Worker call to OpenAI Responses with strict schema; deterministic on-device parser is labeled as fallback. | Conditional live. Model output remains an estimate and requires teacher review. |
| Funding matches | Category-based local heuristics generate DonorsChoose, parent, foundation, business, and district routes with share/open actions. | Guidance only; confidence is category fit, not eligibility or provider approval. |
| Donations | DonorsChoose projects use their official provider link. Separate Stripe Checkout for locally created requests records a local receipt only after server verification. Samples can exercise the same card-entry flow only in Stripe test mode and are excluded from real impact totals. | Testable, but not launch-ready until the recipient/disbursement model, webhooks, refunds, receipts, and reconciliation exist. Stripe does not fund DonorsChoose automatically. |
| Alerts and impact | Local notification cards, favorites, request progress, and verified checkout summaries persist on device. | No remote push, provider webhooks, cross-user real-time updates, or authoritative impact ledger. |

## Required product behavior

### Provenance and degraded operation

1. Every need must show `DonorsChoose`, `Refill community`, or `Sample data` provenance.
2. Sample needs must be unmistakable, may use only Stripe test-mode checkout, and must never charge a real card or count as real impact.
3. Cached provider data must retain its original provenance and expose a stale/offline state when appropriate.
4. Missing provider fields must remain unavailable or use clearly generic UI; Refill must not invent a teacher headshot, biography, years taught, student count, or provider-verified item detail.
5. The launch version must use an exact, tested CA-19 boundary/ZIP policy or describe its broader California coverage without claiming district precision.

### Teacher workflow

1. A teacher can dictate or type a request, choose whether to use live AI, and review all generated content before saving.
2. Model-estimated unit prices, totals, quantities, and urgency are editable before saving; teacher-entered student counts and all estimates require review and are never authoritative quotes.
3. A saved local request remains distinct from a published DonorsChoose project.
4. Funding routes identify whether an action opens an official provider workflow or creates shareable draft copy; eligibility language must remain advisory.
5. Production publishing requires authenticated teacher ownership, a shared request API/database, moderation, audit history, and status synchronization.

### Supporter workflow

1. Feed, browse, detail, save, search, filters, sharing, and source links work for each available need.
2. Funding progress from DonorsChoose reflects the provider response. A locally verified Stripe payment may update only Refill's local display until authoritative synchronization exists.
3. Live checkout must be unavailable for samples; all checkout must be unavailable for closed/funded projects, invalid amounts, missing configuration, or unverifiable payment state.
4. Success is shown only after server-side Stripe retrieval confirms paid status, amount, currency, and project ID.
5. Production must choose one explicit payment model:
   - referral: send supporters to the official DonorsChoose funding URL; or
   - merchant: Refill collects through Stripe under an approved legal recipient, disbursement, refund, tax, webhook, and reconciliation process.

The two models must not be represented as equivalent transactions.

## Integration requirements

- The iOS app receives only public base/callback configuration. DonorsChoose, OpenAI, and Stripe credentials remain in Cloudflare Worker secrets.
- `/v1/needs` fails closed without the DonorsChoose key. The app owns the labeled cache/sample fallback; the Worker never fabricates provider data.
- `/v1/ai/parse` uses OpenAI Structured Outputs, bounds input/output, treats teacher text as untrusted, disables response storage, and validates the result again before returning it.
- Checkout uses Stripe-hosted payment pages, a client-generated idempotency key, Worker-owned HTTPS-to-app return bridges, bounded USD amounts, callback/session validation, and server-side verification. Webhooks are required for durable production fulfillment.
- Authentication must be user-scoped. A static bearer token embedded in iOS is not an acceptable public-release control; CORS is not authentication.
- Upstream errors exposed to clients must be safe and must not leak keys, authorization headers, provider bodies, or keyed URLs.

## Privacy, safety, and accessibility

- Collect the minimum profile and request data. Do not solicit student names, health details, photos, or other child-identifying content.
- Explain before live AI use that request text and selected classroom context leave the device. Provide an on-device alternative.
- Document Stripe and DonorsChoose as separate processors/recipients, with accurate retention, refund, tax-receipt, and deletion language.
- Replace `UserDefaults` with authenticated, protected storage appropriate to the final data model; provide account deletion/export and retention controls.
- Preserve Dynamic Type, VoiceOver labels, sufficient contrast, reduced-motion behavior, and clear non-color provenance/status cues.

## Launch gates

Public release is blocked until all of the following are complete:

1. Provider agreements and credentials for the intended DonorsChoose use, including separate transactional approval if applicable.
2. Exact geography behavior and copy that agree with the shipped feed.
3. User authentication, ownership authorization, shared persistence, moderation, and account deletion/export.
4. A reviewed payment model with Stripe test/live separation, webhook reconciliation, refunds, disbursement, receipts, support operations, and no double counting.
5. Privacy policy/consent, child-data review, abuse/rate controls, secret rotation, redacted observability, and incident response.
6. iOS unit/UI tests plus end-to-end tests for live, cached, sample, AI fallback, checkout cancel, checkout failure, and verified success states.

## Acceptance criteria

- With no backend URL, onboarding and request drafting work; the feed is labeled sample and test card checkout is disabled.
- With a healthy Worker and approved DonorsChoose key, returned projects are labeled DonorsChoose, provider links remain HTTPS DonorsChoose URLs, and a fresh cache is usable during a later outage.
- Missing or malformed provider fields do not crash the app or become fabricated profile facts.
- Live AI reports the returned model; unavailable/transient AI errors use a visibly labeled deterministic fallback; validation errors are not silently hidden.
- Stripe test checkout cannot create a local donation before verification and rejects amount, currency, session, or project mismatches.
- Worker type-check/tests and the iOS simulator build pass using the commands in `README.md`; provider tests do not require live accounts.

## Outcome targets

These are post-launch targets, not current measurements:

- At least 70% of teachers who start a request reach the review screen; at least 50% save or publish through an approved route.
- At least 80% of supporters who tap a funding action reach the selected official provider or checkout page.
- At least 99% agreement between displayed source funding values and the most recently fetched provider payload.
- At least 99.5% successful, crash-free feed loads when either live data or a valid cache is available.
- No payment is recorded as verified without authoritative provider confirmation, and all production payment events reconcile to the operational ledger.
