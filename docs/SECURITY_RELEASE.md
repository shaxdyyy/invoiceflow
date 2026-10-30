# Confidential document release

31 October 2026

Production activation completed after explicit owner approval. Both migrations are applied. Existing record counts are unchanged: 2 profiles, 5 invoices, 12 documents and 5 audit entries. The production URL is https://invoiceflow-eight-omega.vercel.app/ .

## Implemented
- Company membership and database boundaries for invoices, documents, activity, history, storage and assistant queries. Existing records stay in the original company. New accounts must create a separate company or use a single-use 24-hour invitation.
- Manager privileges require a signed AAL2 session after authenticator verification. The existing single-manager correction/approval flow remains.
- PDF and JPG/JPEG uploads join DOCX, XLSX and TXT. 3 MB/file, one invoice/file, PDF maximum 20 pages. Actual file bytes are validated before registration. PDF scripts/attachments, macros/embedded Office programs, external Office relationships, formulas and invalid files are rejected. JPEG decoding has a pixel bound. This is content validation, not a full antivirus service.
- Original previews/downloads use an authenticated, no-store API and temporary browser Blob URLs. The application does not generate bearer document links. Database and Storage RLS still apply to direct provider requests. App original opens are recorded without copying document contents into security events.
- Per-company encrypted Gemini credentials. Cloud processing is disabled by default and requires explicit manager consent. Existing encrypted credentials are preserved. A global environment key cannot bypass company consent. Unpaid Gemini services must not receive confidential information under Google's current terms.
- Browser sign-out after 15 minutes without user activity. Restricted browser capabilities, CSP, no framing, nosniff, HTTPS HSTS, no API caching.
- Exact TypeScript integer-paise calculations using BigInt, plus independent PostgreSQL numeric arithmetic at persistence and approval. AI extracts printed facts and cannot set the check outcome. Unsupported fractional quantities or complex charges require source verification.

## Verified before release
- 50 automated tests passed.
- 68 existing database assertions and 40 new company/MFA/upload assertions passed in isolated PostgreSQL.
- 500 generated decimal calculation comparisons passed, including one-paise mismatch blocking.
- Actual PDF text parsing preserves wrong printed totals. An active-JavaScript PDF is rejected. Actual JPG bytes decode and invalid byte signatures fail.
- TypeScript and optimized build passed. Production dependency audit: zero reported vulnerabilities.

## Production verification
- 40 company/MFA/upload assertions passed against the live database. All fictional fixtures and temporary authorization settings were rolled back.
- Deployed browser demo: supported upload formats visible, practice TXT extraction read-only for employees, independent INR 700 calculation visible, a one-paise mismatch blocked, correction and same-manager approval passed, approved fields locked and correction history retained.
- Privileged company RPC implementations moved into the private schema behind unchanged invoker wrappers. The new exposed-definer advisory is resolved.
- Live authenticated Gemini and owner authenticator enrollment were not performed. Owner must complete their authenticator setup privately.
- The advisor reports leaked-password screening disabled. This is a Supabase Pro-and-above feature; no paid upgrade was enabled. The five private-table no-policy notices are intentional deny-by-default tables with no client grants.

## Boundaries
This release is not a penetration-test certification or a guarantee against every attack. The same manager can correct and approve as requested. No independent approver is required. A company still needs an approved provider arrangement, retention policy, malware scanning service if required, and tested backup/recovery appropriate to its deployment. No paid service was enabled. Never describe a risk score as proof of fraud.

## Owner steps
Sign in, open Settings > Company security, set up an authenticator, and verify its six-digit code. Manager privileges unlock only after verification. If cloud AI is appropriate for the data, enable the company preference after reviewing the terms and then use the retained/configured Gemini connection. Use fictional examples with unpaid Gemini access.

## Sources
- https://supabase.com/docs/guides/storage/buckets/fundamentals
- https://supabase.com/docs/guides/auth/auth-mfa
- https://ai.google.dev/gemini-api/terms (read 31 October 2026)
