> Enterprise upgrade prepared: DOCX/XLSX/TXT uploads, matching, risk controls, exception plans and invoice assistant. See [upgrade guide](docs/ENTERPRISE_UPGRADE.md) for scope, demo instructions, validation and release status.

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

## Upload-first workflow

Choose **Upload invoice** and drop in a PDF, JPG/PNG/WebP image, or text invoice. Limits: 3 MB and 10 PDF pages. A complete, unambiguous extraction is saved and checked automatically. Uncertain or missing fields are shown beside the original for confirmation. The printed total is preserved; it is never replaced by a calculated total.

- **Local reading:** PDF text extraction and browser OCR work without a cloud API key. These are explicitly labeled local readers, not simulated Gemini. OCR downloads its English model/worker assets and needs browser network access on first use. Complex layouts can require manual corrections.
- **Gemini:** Settings → Google AI Studio → paste a free-eligible key → Test & connect. Manager access is required. The key is tested with a small generation request, encrypted using AES-256-GCM on the server, and saved in a private database schema. It is never returned to browser code or committed to Git.
- **Source documents:** live originals are stored in a private Supabase bucket. Employees see their own files; managers can inspect the team originals. Temporary signed links allow source review. Demo originals remain available only until refresh.
- **Practice:** the upload dialog includes **Try a practice PDF**. It runs a real generated sample through the document reader and checker, without pretending to call Gemini.

## AI configuration and verification

A Gemini connection is not currently supplied by the owner. The integration is implemented, but real provider extraction remains unverified until a valid key is connected and tested. Do not present local reading as a live LLM result.

The owner can also configure `GOOGLE_GENERATIVE_AI_API_KEY` in Vercel, which takes precedence over the encrypted in-app key. Default model: `gemini-3.5-flash-lite`; `gemini-3.8-flash` is selectable. Confirm model access, quota and free-tier eligibility in Google AI Studio. The application cannot inspect the provider billing plan. No paid fallback is enabled.

The model extracts structured, schema-validated invoice facts. Missing values are nullable and flagged, not invented. A separate tool-calling reviewer runs `check_invoice` and `draft_review`; it cannot approve or pay. Every saved invoice is rechecked by authoritative database logic, independently of the LLM.

**Privacy:** Gemini receives the uploaded document and invoice fields when connected. Free-tier data terms may allow product improvement. Use fictional/anonymized data unless authorized. Local extraction does not send document content to Google, although OCR software assets are downloaded to the browser.

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

For a new database, apply `database/001_invoiceflow.sql` followed by `database/002_documents_and_gemini.sql`. Generate a random review secret and a separate random manager setup code. Store their SHA-256 hex digests in `private.settings` with keys `review_hash` and `setup_hash`. Set the original review secret only in `REVIEW_SERVER_SECRET` on the server; keep the original setup code only in the owner's `INVOICEFLOW_SETUP_CODE` environment variable. Neither secret belongs in Git.

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

The prototype reads INR invoice PDFs/images/text and also supports manual entry. It does not validate statutory taxes, verify authenticity, integrate an ERP, or transfer funds. Extraction can be wrong; source review and the final human approval remain important. The INR 10,00,000 limit is a demonstration policy, not a business or legal rule. Owner activation must be completed before live approvals. Real AI needs provider configuration. Extraction has at most two attempts per document; individual extracted files need confirmation when fields are uncertain. The in-app test lab runs local checker/policy tests, not a live-model benchmark. Activity views currently display the latest 500 events. Single-workspace prototype; public signup should be replaced by team invitations before broader use.

## Development provenance

This application was developed with AI coding assistance. Team members should review, test and explain the design rather than claim every line was manually authored. Interview findings, impact metrics and user validation have not been fabricated. See the development log for recorded implementation and checks.
