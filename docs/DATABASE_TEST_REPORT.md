# Database integration test report

Executed against the dedicated InvoiceFlow PostgreSQL database on 2026-10-30. Tests used temporary authenticated identities and a transaction that rolled back all test data and settings.

**20/20 assertions passed.**

| Assertion | Result |
|---|---|
| Owner setup code activates manager | PASS |
| Idempotent submission returns same invoice | PASS |
| Duplicate supplier and number blocked | PASS |
| Concurrent review blocked | PASS |
| Forged review result blocked | PASS |
| Wrong total blocked by database | PASS |
| Correction retains original details | PASS |
| Stale review completion blocked | PASS |
| Valid review reaches human approval | PASS |
| Employee approval denied | PASS |
| Direct table mutation denied | PASS |
| Model failure escalates (injected failure) | PASS |
| Database enforces two attempt limit | PASS |
| Other employee cannot read invoices | PASS |
| Other employee cannot read activity | PASS |
| Manager can see team invoice | PASS |
| Manager approval persists | PASS |
| Repeated approval blocked | PASS |
| Completed invoice review is a no-op | PASS |
| Manager self-approval blocked | PASS |

Reproducible script: `tests/database.sql`. Requires a disposable/dedicated project with schema installed, no pre-existing manager, and configured settings. Inspect before running on any project. These tests verify database enforcement; they do not claim a real model provider was called.
