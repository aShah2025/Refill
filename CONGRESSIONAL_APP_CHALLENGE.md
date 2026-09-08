# Refill — Congressional App Challenge Readiness

Last reviewed: September 7, 2026

The official 2026 student flyer lists **October 26, 2026** as the submission deadline. Confirm district-specific eligibility and instructions before submitting: <https://www.congressionalappchallenge.us/>.

## Recommended judging build

Use the app's clearly labeled demo mode for the recorded submission and judging backup. It demonstrates the complete teacher and supporter journeys without depending on a third-party API, accepting real money, or exposing credentials.

Suggested two-minute demo flow:

1. Explain the problem: teachers spend personal money on classroom supplies.
2. Complete role-based onboarding as a teacher.
3. Type or dictate a classroom need, use on-device analysis, review every generated item and price, and save it.
4. Show matched funding routes and the outreach draft.
5. Switch to the supporter experience, filter classroom needs, open a need, favorite it, and show the test-only donation experience.
6. End on Impact and explain the distinction between sample, provider, and processor-verified data.

## Verified in this repository

- iOS 17+ SwiftUI app builds for the iOS Simulator.
- Teacher and supporter onboarding and local workflows function without a backend.
- Sample data is visibly labeled and does not count as real impact.
- The local card sandbox accepts Stripe's standard test card only and never sends card details.
- The Worker has tested boundaries for DonorsChoose listings, OpenRouter/OpenAI request parsing, Stripe Checkout creation, and server-side payment verification.
- Provider secret keys are server-only and are not committed to the app or repository.

## External integration status

The integration code is implemented, but this checkout does **not** contain real provider credentials or a deployed backend URL.

- **DonorsChoose:** requires an approved partner API key. DonorsChoose currently says integrations are available only to partners committing more than $100,000. Official project links remain the safest real-donation route.
- **OpenRouter:** supported as the default live AI provider. Add its key only as a Worker secret; the app continues to work with its labeled on-device parser when the key or backend is unavailable.
- **Stripe:** no test or live secret key is present locally. For a contest demo, use Stripe test mode only. A live key alone does not make fundraising production-ready.
- **Grant centers/foundations:** these are advisory funding matches and shareable outreach drafts. There is no grant-center API or verified eligibility feed in the current codebase.
- **School directory:** uses public NCES reference data from the Urban Institute Education Data Portal. School records are not funding opportunities.

## Before enabling real money or public accounts

These are post-challenge launch requirements, not blockers for a truthful demo build:

- Choose whether Refill is a referral product or the merchant receiving funds.
- Add user authentication, shared persistence, teacher ownership checks, moderation, and account deletion/export.
- Add Stripe webhooks, reconciliation, refunds, disbursement operations, receipts, rate limits, and redacted monitoring.
- Obtain provider agreements and legal/privacy review, especially for student-related data.
- Implement and test exact CA-19 geographic filtering before claiming district-specific coverage.
- Add an automated UI-test target and complete device accessibility testing.

## Safe configuration

Never add provider secrets to Swift files, `Info.plist`, Xcode build settings, or source control. Configure the Cloudflare Worker secrets described in `Backend/README.md`, deploy it, and provide only the public HTTPS Worker URL to the iOS app through `REFILL_BACKEND_BASE_URL`.
