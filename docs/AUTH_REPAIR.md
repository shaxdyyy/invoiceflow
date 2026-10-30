# Confirmation and sign-in repair

31 October 2026

Observed through the connected Supabase project: Site URL was localhost:3000, the redirect allow list was empty, the latest unconfirmed account's links produced one-time-token-not-found errors, and repeated signup requests reached the email-send quota. Invalid-password responses are a separate issue.

Site URL now points to https://invoiceflow-eight-omega.vercel.app and the exact redirect https://invoiceflow-eight-omega.vercel.app/ is allowed. Signup, resend and password recovery explicitly use that production URL. The app handles callback errors, distinguishes expired links from wrong credentials, removes credential fragments after SDK processing, and provides confirmation resend and password recovery with cooldowns.

Confirmation and manager MFA remain enabled. No account was manually confirmed and no password was reset by the agent. Existing confirmed accounts should sign in directly. An unconfirmed user must request and open the newest email once after provider quota resets. Repeated signup attempts do not fix an existing account. Built-in email limits remain and no paid SMTP service was enabled.

Verification: five focused callback/error tests, TypeScript and the optimized build passed. Actual mailbox delivery and employee completion remain owner actions.
