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

No automatic tax compliance claim. No payment execution. Structured data only; document extraction is future work.

## Failure paths and tests

See `tests/database.sql` and `lib/scenarios.ts`. Tests include bad input, valid processing, repeated actions, temporary/persistent model failure state transitions, retry exhaustion, actor permissions and independent success gates. Injected model failures in database tests exercise orchestration, not the real provider.

## Human review and evidence

The manager reads invoice details, check results and advisory review, then records a reason of 5–1000 characters. The action is rejected if the manager is the submitter or the invoice failed checks. Supplier authenticity/business legitimacy remains a human responsibility.
