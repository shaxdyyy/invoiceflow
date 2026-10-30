# Coordinator walkthrough

Explain: InvoiceFlow reduces invoice typing while making the source and changes easy to inspect. Employees upload; a manager verifies the evidence and decides. AI helps read and explain, while code checks the numbers.

1. Show the upload picker: DOCX, Excel (.xlsx), TXT only.
2. Upload the practice TXT. It has two items and a total of INR 700. Extraction runs without typing.
3. Open the comparison. Show original contents on the left, extracted facts on the right.
4. In Employee view, demonstrate that extracted fields are read-only and there is no edit/approve control.
5. In Manager view, demonstrate the correction reason and source-confirmation checkbox.
6. For a test, change the extracted total to INR 900 and save/recheck. The sum remains INR 700, so approval is blocked.
7. Correct it back to the source's INR 700. Record why, compare again and save/approve. One manager performs this; no second manager is required.
8. Show the first extraction and correction history. The original stays unchanged, and before/after values and reasons are retained. The approved document is locked.
9. Re-upload the same original and demonstrate duplicate detection. Show risk reasons and exception guidance. A signal is not proof of fraud.
10. Ask the assistant how missing details should be handled, and search by supplier or invoice number. Show that results open the matching invoice. Demo help/search makes no AI calls; live Gemini is labelled separately.

Be candid about development: the team defined the problem, chose the workflow and limits, used AI-assisted implementation, reviewed the behavior and verified tests. Show GitHub history and test reports. Do not claim code was written unaided.

Validation includes automated Office reader/control tests and embedded PostgreSQL tests of employee write denial, manager correction/approval, original snapshots, audit history, duplicate blocking and a 2,000-invoice search fixture. Live model quota and production activation remain separate checks.
