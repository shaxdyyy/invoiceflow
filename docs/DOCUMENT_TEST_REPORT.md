# Document workflow verification

32 automated tests passed: 18 original checks/policies plus 14 document parsing, file validation and encrypted credential tests. Production build and typecheck passed.

16 transactional database assertions passed in the dedicated Supabase project. Fixtures and changes were rolled back:

- Owner registration permitted; other-owner registration denied.
- Client provider-secret access denied; employee provider changes denied.
- Gemini provenance cannot be claimed without completed extraction.
- Concurrent extraction and forged completion denied.
- Server-authenticated extraction saved; source link is idempotent.
- Direct document mutation denied; two-attempt limit enforced.
- Other employee document/original metadata access denied.
- Upload into another user's folder denied.
- Manager can inspect originals and save server-encrypted configuration.

Scripts: `tests/documents.test.ts` and `tests/documents-database.sql`. Database tests inject extraction results and storage metadata; they do not call Gemini or claim actual uploaded bytes were parsed by the server. Browser document checks and provider verification are recorded separately.

## Browser verification

- Practice PDF: actual PDF text engine extracted both items and total INR 700; saved and checked automatically.
- Practice PNG: actual Tesseract OCR extracted both items and total INR 700; saved and checked automatically.
- Original source access, manager-view switch and final sample approval worked.
- Desktop and 390 × 844 mobile layouts inspected; no horizontal document overflow observed.
- These browser tests used the clearly labeled demo. No real Gemini provider call is claimed without an owner-supplied key.
