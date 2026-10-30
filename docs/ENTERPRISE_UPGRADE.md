# InvoiceFlow enterprise upgrade

## What changed

Invoices can be uploaded as **DOCX, Excel (.xlsx), or TXT only**. PDF, JPG, PNG, WebP, legacy XLS and macro-enabled Office uploads are rejected. Previously stored originals remain readable. One invoice per file, up to 3 MB and 24,000 extracted characters. Excel allows up to five worksheets, 500 rows and 40 columns; replace formulas with values before uploading. Office archives have a 16 MB decompressed limit and a 1,500-entry limit. No macros, embedded instructions or spreadsheet formulas are executed.

DOCX tables and Excel cells are decoded into text on the device. Connected Gemini reads that text and extracts nullable invoice facts. Independent code preserves the printed total and checks calculations. The original is kept privately in the live workspace. DOCX and Excel practice downloads are available in the upload dialog.

## Demonstration steps

1. In the demo, open Settings and choose Manager. Open **Orders & receipts**.
2. Add PO-001 for Paper & Co. Add A5 notebooks: ordered 10, price 50, received 10. Add Desk folders: ordered 5, price 40, received 3. Add receipt GRN-001 and save.
3. Upload the practice TXT or download and upload the DOCX/Excel practice file. Its total is INR 700.
4. Open that invoice. In **Risk & matching**, choose Two-way, enter PO-001, and save. The order matches.
5. Change to Three-way. The folders fail because only three of five were received. A score of 60 and a blocking exception appear.
6. Ask the exception agent for a plan. Demo shows an explicitly labelled rules plan; live uses Gemini, inspects the saved invoice and drafts an advisory plan with evidence and responsible next steps.
7. In Orders & receipts, update folders received to five. In live mode related exception cases are rechecked automatically. Refresh invoice controls to see a resolved match.
8. Try a duplicate with a changed invoice number but identical supplier, date, items and total. It is flagged as a potential duplicate. This is a signal to investigate, not proof of fraud.
9. Open AI assistant. Search by supplier/number, or ask for pending invoices. Click a returned invoice to inspect it. Search-only mode remains available without an AI call.

## Matching rules

Two-way compares invoice supplier, item descriptions, ordered quantities and exact unit prices. Three-way additionally compares received quantities and a goods receipt reference. Quantities from previously approved invoices count against the same order; partial invoices cannot repeatedly bill above the ordered/received quantity. Duplicate invoice item descriptions are aggregated for quantity comparisons. PO item descriptions must be unique. Matching is optional for existing invoices until configured. Employees can configure or strengthen matching; only managers can reduce an already configured control.

Managers record purchase orders and cumulative goods receipts. PO rows are manager-only. Employees see the matching assessment of their own invoices, without access to unrelated orders. Supplier names are normalized for case/punctuation. Item descriptions match after trimming and ignoring case; materially different descriptions require a person to reconcile them.

## Duplicate and anomaly detection

The database checks the entire dedicated workspace for normalized supplier + invoice number duplicates and same supplier/date/amount/item fingerprints with changed numbers. Rejected records are excluded. No other employee's invoice details are returned by this internal check.

The explained score is capped at 100: normalized duplicate 95, duplicate content 80, arithmetic mismatch 60, missing/failed configured matching 60, invalid date order 40, amount above the prototype limit 60, unusually large supplier amount 35, future date 20. Low <25, Medium 25–59, High >=60. Supplier amount outliers require at least five approved prior invoices and an amount greater than three times their median. The score is a rules score, not a trained fraud probability.

Gemini also inspects evidence for additional anomalies and writes an advisory exception plan. AI cannot alter the independent score, clear blocking signals, approve invoices, change financial figures or pay. Database approval checks run again at the decision, with serialized decisions to protect purchase-order quantities. High scores caused by duplicates or failed matching block approval. Nonblocking amount/date anomaly signals remain visible for manager judgment.

## Exception handling and chat

Every completed live invoice review creates or updates an exception case. Rules determine open/resolved; Gemini can inspect and enrich the plan. Updated PO/receipt evidence rechecks affected open invoices automatically and records an audit event. The agent never invents missing values or silently changes original invoices.

The assistant uses bounded tool calls: search accessible invoices, inspect one invoice and its risk assessment, and draft a plan for the selected invoice. Search runs in PostgreSQL with account row permissions, indexed text search, amount/status/date filters, 20-row pagination and a full count. It is not restricted to the first 1,000 rows. Model requests do not contain all 2,000 invoices. Each account has a 20-request rolling 24-hour AI assistant limit, four model steps, no automatic retries and a 35-second timeout. Existing extraction/review budgets still apply. Search-only mode has no model call. Provider free-tier quotas still apply; no paid fallback is configured.

## Release status and approval

Implementation is prepared in the feature branch. Production schema changes and production deployment have **not** been applied. Automatic approval review rejected the initial migration for its persistent production schema/approval/storage changes and overly broad PO visibility. The revised migration restricts PO rows to managers and is tested in an isolated embedded PostgreSQL instance using fictional data.

To release after explicit approval:

1. Apply `supabase/migrations/20261030143512_enterprise_controls.sql` to the dedicated InvoiceFlow project only (`xyqbeirehlvvbxxjwbzd`). It adds purchase order/receipt and exception tables, matching columns, assistant usage limits, search indexes and a database approval gate, and limits new storage uploads to DOCX/XLSX/TXT.
2. Verify database advisors and a transactional live-project permission smoke test.
3. Deploy the tested source to the existing InvoiceFlow Vercel project. Do not set `NEXT_PUBLIC_PREVIEW_ONLY=true` in production.
4. Verify live sign-in, upload, matching, exception case persistence, Gemini chat and existing approvals. Existing invoice and document rows are preserved. Existing PDF/image originals remain accessible, though new uploads are disallowed.

The preview build sets `NEXT_PUBLIC_PREVIEW_ONLY=true`, disabling database clients and live sign-in. It uses only fictional demo data and makes no cloud model calls. Do not promote the demo preview to production; rebuild the approved production source.

## Validation

- Automated extraction/control tests cover DOCX tables, XLSX values, formula rejection, compression-bomb limits, file allowlisting, preserved printed amounts, matching, duplicates, and risk baselines.
- Embedded PostgreSQL executes the initial schemas and exact upgrade SQL; existing database assertions plus enterprise assertions verify RLS, server authorization, approval gates, receipt rechecks, cumulative quantities, quota and searching 2,000 invoices beyond the first 1,000.
- TypeScript and a Next.js production build are required.
- Gemini network behavior and live-project migration remain release checks, not claims from local tests.

### Completed verification on the prepared branch

- 50 automated tests passed, including a PostgreSQL integration suite with **66 database assertions** (36 existing and 30 enterprise assertions).
- TypeScript and optimized Next.js build passed.
- `npm audit --omit=dev --audit-level=moderate`: zero vulnerabilities. ExcelJS uses a pinned UUID override to address its upstream dependency advisory.
- Browser preview: practice TXT extracted and auto-saved at INR 700; a manager created PO-001 with only three of five folders received; three-way matching showed 60/100 High risk; an attempted approval was blocked; rules exception plan displayed; assistant search returned the two Paper invoices.
- The screenshot `docs/screenshots/enterprise-risk.jpg` records the browser verification using fictional data.
- Live Gemini requests and production migration have not been tested in this upgrade. They remain release checks after approval.
