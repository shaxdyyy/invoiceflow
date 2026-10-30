# Explain and demonstrate InvoiceFlow

## Honest introduction

“We selected invoice review as our proposed enterprise workflow. We used AI-assisted development to implement it. Our team must understand and verify the input rules, independent checks, human approval and failure controls. User validation is still to be completed unless we supply actual interview notes.”

## Preparation

1. Confirm organizer acceptance of invoice review and obtain permitted samples.
2. Speak to a real invoice reviewer. Record their process and feedback accurately; do not invent quotes or results.
3. Open the app. Explain that the labeled demo is browser-only and uses no live AI.
4. For the shared backend demo, create an employee account and a separate manager account. Confirm emails. The owner activates the manager using Settings and the one-time code in Vercel. Do not put credentials in slides.
5. For live AI, add a free-eligible provider key to server settings, redeploy and perform an actual smoke test before claiming the model works.

## Demonstration

1. As employee, submit 10 notebooks × INR 50 with total INR 700.
2. Run review. Show the arithmetic mismatch and blocked approval.
3. Correct total to INR 500. Show the before/after snapshot in history.
4. Run review again. Show Rules-only or AI-assisted accurately.
5. As a different manager, open Approvals and inspect all evidence.
6. Enter “Verified against the purchase request” and approve.
7. Refresh and show the saved decision and timestamp.
8. Open Test lab, run the scenarios and export the results.
9. Show GitHub commits, `docs/WORKFLOW_SPEC.md`, actual test reports and development log.

## Easy explanations

- Frontend: the screens the employee and manager use.
- Backend: the code that receives requests and enforces the process.
- Database: the shared record of invoices, users and history.
- Agent: an AI assistant allowed to call specific review tools.
- Checker: independent rules, so the AI cannot decide whether arithmetic is correct by opinion.
- Human gate: a real manager must decide; the agent has no approval tool.
- Retry limit: after two attempts, processing stops for human investigation.

## Expected questions

**Why not only a chatbot?** A chatbot response does not persist workflow state, enforce roles, block duplicates or save a manager decision.

**Why AI if rules can check totals?** Rules provide factual gates. AI adds an understandable contextual review and proposed next step. We do not use AI where exact arithmetic is better.

**What is genuinely validated?** Show only actual interview evidence and executed tests. The test reports distinguish local logic, database integration, UI checks and provider verification.

**What does it cost?** The prototype uses free-tier hosting/database and optional eligible free-tier model access. Limits apply; no paid fallback is configured.

**What is incomplete?** PDF extraction, real supplier verification, accounting integrations, business validation and live model verification until a provider key is tested.

## New upload-first demonstration

Open Upload invoice → Try a practice PDF. Explain that the demo reads the actual sample PDF on-device, not through Gemini. A complete extraction should save and check automatically. Open the source and compare extracted line items. In demo mode, use “Try the manager view” to demonstrate the separate final decision.

For real AI, sign into the live workspace as a manager and open Settings → Google AI Studio. Connect an eligible free-tier key using Test & connect. Only claim a live model demonstration after successfully reading a sample document with Gemini. Show the extraction engine label and original source.

Use the video-inspired design as a visual reference, not as copied implementation. Explain that interface decisions prioritize one upload action, readable text, explicit exception handling and a final human decision.
