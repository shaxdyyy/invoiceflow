# InvoiceFlow workflow specification

## Problem and users

Supplier bills require repeated checks and approval follow-up. This is a proposed problem to validate with actual accounts staff, not an already measured business finding. Users are employees submitting invoices and separate managers making decisions. Confirm invoice checking is allowed with the organizers.

## Inputs

Supplier, supplier invoice number, invoice date, due date, controlled category, 1–30 line items (description, positive integer quantity, two-decimal unit price), explicit tax amount, submitted total and optional notes. Currency: INR. A client UUID makes submission retries idempotent.

## State machine

`submitted → processing → pending_approval → approved | rejected`

`processing → needs_correction → submitted` (correction retains original snapshot)

`processing → escalated → processing` (only while an attempt remains)

Two-minute-stale processing runs may be recovered; a fresh run identifier invalidates late results from the previous run. Approved/rejected records are terminal. Re-review of a completed or pending invoice returns the existing record without another review.

## Steps and tools

1. Authenticate with Supabase and authorize record access.
2. Validate schema, controlled categories and unique normalized supplier/number in the database.
3. Reserve review atomically and create a run ID; increment bounded attempt count.
4. Run a deterministic checker independently of the model.
5. If a required check fails, return for correction without using an LLM.
6. If no model key exists, create an explicitly labeled rules-only review.
7. Otherwise the AI must call `check_invoice`, then `draft_review`. The first tool verifies data; the second prepares advisory text. Neither can approve or mutate invoice facts.
8. Authenticate review completion with a server-only secret. Database independently recomputes required arithmetic/date/limit checks.
9. If checks pass, pause for human approval. The approver must be a manager other than the submitter.
10. Record the decision, reason and actor atomically in persistent history.

## Five bounds

| Bound | Enforcement |
|---|---|
| Maximum iterations | 2 review attempts per invoice revision; max 3 model steps per attempt; SDK retries disabled |
| Success gate | Database schema validation, exact total, date order, uniqueness, amount policy; human approval remains required |
| No-op | Repeated client submission returns existing row; completed/pending review does not run again; repeated decision is blocked |
| Escalation | Model errors, timeout, missing required tool output or exhausted attempts require human investigation; invoice facts are never invented |
| Budget | Max 12,000 input characters; max 400 output tokens per step; max 3 steps; 25-second model timeout; 10 review starts per user in rolling 24 hours; no automatic paid fallback |

A correction resets per-revision attempts, but does not bypass the per-user daily limit. Model input tokens vary by tokenizer; the character limit caps payload growth. Real provider token charges, if any, depend on the account; a free API key does not itself prove eligibility. Reported token count is available on successful calls; a failed provider request may consume tokens without returning a usable count.

## Fixed demonstration checks

- Required fields and valid calendar dates.
- Quantity × unit price + entered tax must equal submitted total, using exact decimal logic.
- Supplier + invoice number uniqueness ignores case and surrounding spaces, including across concurrent submissions.
- Due date must not precede invoice date.
- Expected total must be ≤ INR 10,00,000 (prototype policy).

No automatic tax compliance claim. No payment execution. PDF/image/text document ingestion is implemented; structured invoice facts remain the authoritative input for checks.

## Failure paths and tests

See `tests/database.sql` and `lib/scenarios.ts`. Tests include bad input, valid processing, repeated actions, temporary/persistent model failure state transitions, retry exhaustion, actor permissions and independent success gates. Injected model failures in database tests exercise orchestration, not the real provider.

## Human review and evidence

The manager reads invoice details, check results and advisory review, then records a reason of 5–1000 characters. The action is rejected if the manager is the submitter or the invoice failed checks. Supplier authenticity/business legitimacy remains a human responsibility.

## Document ingestion extension

Upload PDF, PNG, JPEG, WebP or TXT (3 MB maximum, PDF ≤10 pages). Live files go to a private bucket and get an owner-scoped `documents` record. Automatic extraction uses Gemini when connected, otherwise an explicitly labeled on-device PDF/text/OCR reader. A complete extraction is saved and reviewed without retyping. Missing values, unknown currency and ambiguous fields require confirmation against the source.

Gemini structured extraction has at most two attempts per document, a 35-second timeout, 3,500 output tokens per attempt, no SDK retries and a per-user daily extraction budget. Source facts are schema-validated; wrong printed totals are retained for deterministic validation. Local text is capped at 24,000 characters. The owner must confirm free-tier eligibility; the app cannot prove the provider billing plan.

Original files cannot be overwritten through application policies. Linking is idempotent and creates an invoice activity event. Gemini provenance can only be attached after a server-authenticated extraction result. A document remains visible in Documents even if extraction fails or requires input. Provider configuration uses server-side AES-256-GCM encryption; only managers can update it, and server authorization is required to retrieve the ciphertext.
