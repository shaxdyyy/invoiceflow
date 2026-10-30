# InvoiceFlow workflow specification

Upload → server extraction → independent checks → one-manager comparison/correction/decision → immutable history.

- Input: one INR invoice per DOCX, Excel (.xlsx), or TXT file. No new PDF/image uploads. Private originals are immutable. Word/Excel readable previews preserve contents and tables, though exact application formatting can differ.
- Extraction: the server reads the stored original and runs configured Gemini or the rules reader. Missing values remain null and are flagged. Printed totals are preserved for calculation checks. Initial extraction, source text and SHA-256 file hash are stored separately from manager corrections.
- Employees: can upload and view their documents/invoices. They cannot edit extracted values or submit replacement invoice payloads through the old client APIs.
- Managers: see original and extracted fields side by side, correct extraction errors with a reason, save/recheck or save/approve. The same manager may correct and approve, including their own upload; no second manager is required. Approval requires the current independent checks to pass. Unverifiable documents may be rejected.
- Checks: required fields, date order, exact quantities × unit prices + tax, INR currency, prototype amount limit, exact-file re-upload detection, normalized supplier/invoice-number duplicates and duplicate invoice-content signals. Supplier amount outliers require five approved historical invoices. Risk is a rule score, not fraud probability.
- Missing details: route to the manager without fabricating facts. Ask for a readable/corrected supplier document where necessary. Record what was checked and why a correction was made.
- Audit: first extraction and original never change. Each manager correction stores before/after values, reason, actor, revision and time. Finalized documents are locked. Optimistic revisions reject stale saves. Repeated submissions and repeated approvals are bounded or idempotent.
- AI assistant: scoped invoice search, workflow guidance, missing-field/document inspection and anomaly/exception plans. AI cannot edit invoice facts, approve, pay, clear blocking evidence or reveal credentials. Search uses database RLS and 20-row pagination, including beyond 1,000 records; model prompts never contain the entire invoice store.
- Limits: 3 MB upload; 24,000 decoded characters; Office archive 16 MB decompressed, 1,500 entries; Excel ≤5 sheets, 500 rows, 40 columns, saved values only; ≤30 invoice items. AI assistant 20 requests/account/day, four steps, 35 seconds, no retries or paid fallback. Provider free-tier eligibility and quota remain external limits.
- Removed: orders, goods receipts and all two-way/three-way matching.

Existing legacy originals remain accessible. Where the prior workflow had no extraction snapshot, prior invoice values are clearly marked as a legacy import rather than a new extraction.

The prepared database migration and production release require activation approval. Current validation and deployment status are recorded in ENTERPRISE_UPGRADE.md.
