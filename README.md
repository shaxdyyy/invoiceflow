# InvoiceFlow

A working invoice review and approval application for **Problem Statement 2: Build and Deploy a Pre-Tested Enterprise Workflow**.

InvoiceFlow combines structured invoice submission, deterministic checks, an optional tool-calling AI reviewer, a separate human approver, and a persistent audit trail. It does not make payments.

**Live application:** https://invoiceflow-eight-omega.vercel.app

**Deployment:** the initial release was deployed directly. To enable automatic deployments on future GitHub pushes, connect the GitHub account under Vercel account settings, then link this repository in project Settings → Git.

## Start here

- **Try the demo:** open the deployed app. The clearly labeled demo uses fictional records stored only in that browser. No model calls are made.
- **Use live records:** choose **Open live workspace**, create an account, confirm your email, and sign in. Employees see their submissions; managers see the team queue. Live records use the shared Supabase database.
- **First manager:** the repository/Vercel owner retrieves `INVOICEFLOW_SETUP_CODE` from Vercel project environment settings. Sign in, go to Settings, and enter that code. It can be redeemed once. Managers can promote trusted members in Settings.
- **Make a decision:** submit as an employee, run review, then sign in as a different manager. Self-approval is blocked in the database.

## What works

- Responsive dashboard, searchable invoice table, filters and CSV export.
- Structured INR invoice entry with multiple line items and explicit tax amount.
- Required-field, arithmetic, date, duplicate and prototype amount-limit checks.
- Integer-paise calculations in TypeScript and exact numeric calculations in PostgreSQL.
- Corrections preserve the original invoice snapshot in the activity log.
- Idempotent submissions, atomic state changes, stale-run protection and duplicate-decision protection.
- Authenticated employee/manager permissions enforced by database RLS and RPCs.
- Bounded AI tool calls, no-op behaviour, escalation, human approval and audit export.
- Executable test lab, automated tests, workflow specification and coordinator walkthrough.

## AI: implemented, optional, not silently simulated

Without a model key, live reviews run in **Rules-only** mode. The app explicitly labels this. It is a usable validation/approval workflow, but it is not a live LLM demonstration.

To enable actual AI, add an eligible free-tier `GOOGLE_GENERATIVE_AI_API_KEY` to Vercel server environment variables and redeploy. Optionally set `GOOGLE_MODEL`; the default is `gemini-2.5-flash`. Verify model availability and free-tier eligibility in your account before use. Do not enable billing merely to bypass quota. There is no paid fallback.

The AI calls `check_invoice` against server-loaded data, then `draft_review` to prepare advice. It has no approval, payment or arbitrary execution tool. Tool order and inputs are constrained; the database independently rechecks approval gates. A missing tool result, timeout or model failure escalates instead of inventing a result. Real provider access remains unverified until a key is configured and tested.

**Privacy:** when AI is enabled, invoice fields are sent to Google. Free-tier provider terms may allow data to be used for product improvement. Use fictional/anonymized inputs for this prototype. Never include confidential supplier information without permission.

## Local setup

Requires Node.js 22+ (Node.js 24 used for verification).

```bash
npm ci
cp .env.example .env.local
# Fill the variables for your dedicated Supabase project.
npm run dev
```

```bash
npm run typecheck
npm test
npm run test:report
npm run build
```

For a new database, apply `database/001_invoiceflow.sql`. Generate a random review secret and a separate random manager setup code. Store their SHA-256 hex digests in `private.settings` with keys `review_hash` and `setup_hash`. Set the original review secret only in `REVIEW_SERVER_SECRET` on the server; keep the original setup code only in the owner's `INVOICEFLOW_SETUP_CODE` environment variable. Neither secret belongs in Git.

The connected project has already been provisioned separately from CampusFix. Environment values are kept out of source control.

## Deployment

Import `shaxdyyy/invoiceflow` into Vercel as a Next.js project. Set the variables in `.env.example` plus the owner-only setup code, then deploy. No service-role key is required.

In Supabase **Authentication → URL Configuration**, set Site URL and allowed redirect URLs to the deployed domain. Keep email confirmations enabled. If confirmation redirects to the default URL before this is configured, return to the application and sign in after confirming. Built-in email delivery has limits; inspect the provider dashboard if confirmation is delayed. No paid email/SMS service is required for the prototype.

Vercel Hobby is intended for eligible personal, non-commercial use and has usage caps. Supabase Free also has quotas and inactivity behaviour. The code does not opt into any paid plan.

## Architecture and trust boundaries

- **Next.js / React / TypeScript:** interface and authenticated review endpoint.
- **Supabase Auth:** verifies identities; no user-selectable live role.
- **PostgreSQL:** authoritative checks, row locks, state transitions, role enforcement, immutable-to-app activity records.
- **Vercel AI SDK + Google provider:** optional bounded agent review.
- **GitHub Actions:** typecheck, automated tests and production build.

Public RPC wrappers are security-invoker functions. Privileged implementations are in a non-exposed private schema, check identity/authorization, use fixed empty search paths and have explicit grants. Direct client table writes are revoked. The server-only review secret prevents authenticated clients from forging review completion.

The database owner can administratively alter records; this is an application-level audit trail, not cryptographic tamper-proof storage.

## Documentation

- [Workflow specification](docs/WORKFLOW_SPEC.md)
- [Coordinator demonstration](docs/COORDINATOR_GUIDE.md)
- [Actual development log](docs/DEVELOPMENT_LOG.md)
- [Automated scenario results](docs/TEST_REPORT.md)
- [Database integration results](docs/DATABASE_TEST_REPORT.md)
- [Database tests](tests/database.sql) — transactional; fixtures roll back.

## Scope and limitations

The prototype accepts manually entered INR invoices; it does not parse PDFs, validate statutory taxes, verify authenticity, integrate an ERP, or transfer funds. The INR 10,00,000 limit is a demonstration policy, not a business or legal rule. Owner activation must be completed before live approvals. Real AI needs provider configuration. The in-app test lab runs local checker/policy tests, not a live-model benchmark. Activity views currently display the latest 500 events. Single-workspace prototype; public signup should be replaced by team invitations before broader use.

## Development provenance

This application was developed with AI coding assistance. Team members should review, test and explain the design rather than claim every line was manually authored. Interview findings, impact metrics and user validation have not been fabricated. See the development log for recorded implementation and checks.
