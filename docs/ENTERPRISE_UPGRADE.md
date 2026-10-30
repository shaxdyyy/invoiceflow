# InvoiceFlow source comparison and single-manager review

The final scope replaces the earlier procurement preview. Orders, receipts and two-/three-way matching have been removed.

## User flow

1. Upload a DOCX, Excel (.xlsx) or TXT invoice (one invoice per file, up to 3 MB). Originals are private and immutable. Existing PDF/image originals remain viewable, while new uploads accept only the three requested types.
2. The server downloads the saved original, reads its text/tables and extracts facts using configured Gemini or the local rules reader. The browser cannot submit replacement invoice values. The initial extraction, source text and file hash are preserved.
3. Complete extractions become invoices automatically. Missing or uncertain data goes to Documents for manager review without invented fields. Employees see read-only fields and cannot change invoice facts through either the interface or old database write APIs.
4. Open the comparison: original text/tables on the left, extracted fields, missing-value warnings, calculations, duplicate/risk checks and exception help on the right. Word/Excel visual formatting may differ from the source application; download the original for exact layout. Legacy PDF/image originals can still be displayed.
5. A manager can correct extraction mistakes with a reason. Save & recheck recalculates totals and checks dates, duplicates and risk. Save & approve records corrections and approves in one operation if checks pass. No second manager is required, including for the manager's own uploads.
6. The original and first extraction remain unchanged. Correction history records actor, time, reason, revision and before/after values. Approved/rejected documents are locked; stale revisions cannot overwrite a newer edit.

## Integrity and exceptions

The server hashes the original file and catches re-uploads. The database also flags normalized supplier/number duplicates and matching supplier/date/amount/item fingerprints even with a changed invoice number. A potential duplicate is a reason to investigate, not proof of fraud. A manager can reject an unverifiable or incomplete document instead of inventing facts.

Risk scores are explained rule scores, not fraud probabilities. Amount outliers need at least five approved supplier invoices and an amount more than three times the median. AI can inspect anomalies and prepare an advisory exception plan but cannot alter invoice facts, clear blocking signals, approve or pay.

The invoice assistant searches the entire accessible invoice set using indexed, paginated database queries (20 rows per page), explains the workflow and helps with missing fields, correction steps, duplicate warnings and exceptions. Document-specific help can inspect the accessible original/extraction. The AI account budget is 20 requests per 24 hours, up to four steps and 35 seconds per request, with no retries or paid fallback. Search-only mode has no AI call. Provider free-tier quota still applies.

## Migration and validation

Apply the two prepared migrations to the dedicated InvoiceFlow project only. The first adds risk, exception and search support and restricts new upload MIME types. It creates no procurement tables. The second adds document snapshots, file hashes, manager correction audit and single-manager decision rules, and disables old client create/amend/link/extraction-completion write paths. Existing originals and invoice rows are preserved. Legacy invoice values without a stored extraction are clearly labelled as an import from the previous workflow, and need comparison before a new decision.

The embedded PostgreSQL suite verifies 36 historical checks before applying the final permissions and 32 final workflow assertions, including employee edit denial, immutable snapshots, correction audit, stale revision rejection, same-manager correction/approval, rejection of incomplete documents, exact file duplicates and searches across 2,000 invoices. Office reader tests cover DOCX tables, Excel values, formula rejection, ZIP limits and GST tables. The final suite has 44 automated tests. TypeScript, Next.js build, dependency audit and browser smoke tests are release checks.

Production activation is pending explicit approval following automatic review rejection of live permission, approval, storage and legacy-record changes. The reviewable preview uses fictional data and disables live database access.

### Final validation and release boundary

44 automated tests pass, including 68 PostgreSQL assertions (36 historical and 32 final). TypeScript, optimized Next.js build and dependency audit pass; the audit reports zero vulnerabilities. Final browser interaction verification was blocked: the connected browser timed out, and the separate test browser reached Vercel Authentication. A requested one-hour preview share link was rejected by automatic approval review because it would grant anyone holding the link access. No protection settings were disabled. The protected preview is available to the Vercel project owner.

Automatic approval review also rejected production migration because the user had authorized implementation but not explicitly activating persistent schema/permission/storage/legacy-record changes. No production database changes or production deployment were applied. The next approval must explicitly cover applying the prepared migration, disabling employee client edits, enabling audited single-manager correction/approval (including own uploads), preserving/importing legacy document snapshots, limiting new uploads to DOCX/XLSX/TXT, and deploying the tested source. No keys or passwords should be pasted into chat.
