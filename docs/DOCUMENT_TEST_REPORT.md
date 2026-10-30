# Document workflow verification

30 automated tests passed: 18 original checks/policies plus 12 document parsing, file validation and encrypted credential tests. Production build and typecheck passed.

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
