# Development log

This records actual work, not a reconstructed claim of manual authorship. Development used AI coding assistance.

## Decisions

- Inspected the supplied repository; it was empty.
- Kept the agreed Next.js/TypeScript application stack and optional direct Google free-tier model access.
- Provisioned a dedicated Supabase project, separate from CampusFix, after the owner selected the existing organization.
- Kept demo and live modes visibly separate. No sample invoice is presented as a real company record.
- Required a separate manager for approval; public signup grants only employee access.
- Used private database implementations and restricted public RPC wrappers; clients cannot directly write workflow tables.
- Added server-only review authorization so clients cannot forge successful model/check completion.

## Implemented

1. Database schema, auth profiles, RLS, explicit permissions and atomic transitions.
2. Invoice entry, independent checker, corrections and duplicate prevention.
3. Bounded tool-calling model adapter with explicit rules-only mode.
4. Manager approval and append-only-to-app event history.
5. Responsive dashboard, searches, filters, exports and test lab.
6. Workflow specification, coordinator guide, automated test reports and CI.

## Verification recorded during implementation

- TypeScript check passed.
- 18 automated checker/policy tests passed.
- 14 downloadable in-app scenarios passed.
- Production build passed.
- 20 PostgreSQL integration assertions passed in a rollback transaction. They exercised real authenticated-role permissions and authoritative state transitions.
- Security advisor: no warning/error findings. One informational finding for intentionally inaccessible `private.settings` (RLS with no client policies).

## Real issues found and fixed

- The initial test command used a process communication socket unavailable in the execution environment. Changed it to Node’s test runner with the TSX import hook; tests then executed successfully.
- Renamed a PL/pgSQL local variable to avoid ambiguity with the `checks` column before end-to-end database tests.

## Verification boundaries

Provider requests need a configured model key. Do not report live model success until that happens. UI/deployment verification results are appended only after actual checks.

## Deployment and browser verification

- Source uploaded through the GitHub connector because the local Git transport had no write credential.
- Direct Vercel production deployment succeeded. Git-based auto-deployment is not linked: Vercel reports that the owner must add a GitHub Login Connection.
- Production URL: https://invoiceflow-eight-omega.vercel.app
- Browser checked the dashboard, executed all 14 test-lab scenarios, reviewed and approved a sample invoice, and confirmed the saved sample record after reload.
- Responsive layout inspected at a 390 × 844 viewport; no horizontal document overflow was observed.
- Sample-mode approval tests use browser-local records. PostgreSQL integration tests separately verify live database permissions and transitions. Live email signup and model provider access are not claimed as verified.
- Manager activation and optional AI-key setup remain owner actions documented in README.
- Fixed dashboard attention filtering so escalation records match the displayed count; approval CSV export now matches the inbox filter.
- Serialized per-user daily review reservations to prevent concurrent requests from bypassing the review-start budget.

## Document-first redesign

- Inspected the user-provided 23-second video reference. Adapted its monochrome typography, pill navigation, generous spacing and motion into an original invoice interface with a CSS-rendered blue orb and animated receipt scanner.
- Consulted official Ramp invoice-processing patterns and Gemini document-processing/model documentation. Used upload → extract → validate → approval as the interaction model; no proprietary source was copied.
- Added private PDF/image/text uploads, browser text/OCR reading, Gemini structured extraction, original-document access and automatic checking after save.
- Added a manager-only in-app AI Studio connection screen, small provider connection test, encrypted key storage and selectable currently documented Gemini models.
- Production build and TypeScript checks passed. 32 automated tests passed, including actual parsing, missing-field behaviour, preserved mismatches and credential encryption. 16 additional transactional document/storage-permission assertions passed.
- A real Gemini key has not been provided; no live provider success is claimed. User-account signup/email delivery and full cloud extraction remain separate owner verification steps.

## Browser verification of the upload-first release

- The deployed practice PDF was generated, read by the actual browser PDF engine and parsed into two line items, an explicit zero tax and INR 700 total. It reached approval automatically without manually entering fields.
- Original PDF preview and source-engine labeling were visible. The demo manager switch and final approval both worked. No browser errors were recorded during that test.
- Desktop and 390 × 844 mobile layouts inspected; no horizontal document overflow observed. Google AI Studio connection panel is present.
- Kept the original preview collapsible so required checks and final decisions remain easy to reach. Added cancellation for on-device reading and a separate image practice option.
- Added tax-component reconciliation tests and low-confidence OCR handling. Model access still requires an owner-supplied key and is not claimed as verified.

- Final deployed image-OCR smoke test passed: generated sample image → actual on-device OCR → two line items and INR 700 → independent checks → approval queue. This was local OCR, not a claimed Gemini request. First use downloaded OCR software assets.


## 30 October 2026 — enterprise feature branch

Implemented Office/text invoice uploads, two-/three-way matching with cumulative quantities, normalized duplicate/content checks, explained anomaly scores, bounded Gemini exception and search tools, manager-only purchase order storage, exception cases, and paginated scoped search. Tested the SQL in isolated embedded PostgreSQL, including a 2,000-invoice fixture. Prepared a demo-only preview; production release awaits explicit approval following automatic review rejection of the initial schema change. Full scope and limitations are recorded in ENTERPRISE_UPGRADE.md.


## 30 October 2026 — revised source-comparison workflow

Removed procurement and matching at the user’s request. Added server-owned extraction snapshots, read-only employee views, side-by-side originals and extracted facts, manager-only corrections with before/after audit, optimistic revisions and single-manager save-and-approve. Preserved duplicates, risk, exception agent and assistant, with workflow help and document inspection tools. Added database integration tests for the final permission model.
