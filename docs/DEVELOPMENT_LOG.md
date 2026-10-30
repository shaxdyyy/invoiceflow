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
