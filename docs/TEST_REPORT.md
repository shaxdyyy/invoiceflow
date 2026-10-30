# Automated scenario report

Generated: 2026-10-30T09:38:41.108Z

These are executable checker and policy scenarios, not a claim that a live model was tested. Database permission and transaction tests are recorded separately.

| Scenario | Expected | Result |
|---|---|---|
| Valid invoice | Pass all independent checks | PASS |
| Incorrect total | Block a INR 200 mismatch | PASS |
| Missing supplier | Reject incomplete input | PASS |
| Duplicate invoice | Block repeated supplier + number | PASS |
| Date order | Block due date before issue date | PASS |
| Money precision | Handle 3 × 0.10 exactly | PASS |
| Retry limit | Stop after two review attempts | PASS |
| Bounded retry | Allow remaining attempt after failure | PASS |
| Already completed / no-op | Do not review an approved invoice again | PASS |
| Approval permissions | Employee cannot approve | PASS |
| Self-approval | Submitter cannot approve their own invoice | PASS |
| Failed success gate | Manager cannot override failed checks | PASS |
| Amount limit | Escalate values outside prototype policy | PASS |
| Normalized duplicate key | Ignore letter case and surrounding spaces | PASS |
