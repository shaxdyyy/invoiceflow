import { z } from 'zod';
import type { InvoiceInput, CheckResult } from './types';
export const limits = { attempts: 2, modelSteps: 3, outputTokensPerStep: 400, requestTimeoutMs: 25000, inputCharacters: 12000 } as const;
const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => !Number.isNaN(Date.parse(v)) && new Date(v).toISOString().slice(0, 10) === v, 'Enter a valid date');
const amount = z.number().finite().min(0).max(100000000).refine(v => Math.abs(v * 100 - Math.round(v * 100)) < 0.00001, 'Use at most two decimal places');
export const invoiceSchema = z.object({
  supplier: z.string().trim().min(2).max(160), invoice_number: z.string().trim().min(1).max(80),
  invoice_date: dateOnly, due_date: dateOnly, category: z.enum(['Office supplies', 'Software & services', 'Equipment', 'Travel', 'Other']),
  items: z.array(z.object({ description: z.string().trim().min(1).max(200), quantity: z.number().int().min(1).max(100000), unit_price: amount })).min(1).max(30),
  tax: amount, total: amount.refine(v => v > 0, 'Total must be greater than zero'), notes: z.string().max(1500).default('')
});
export const normalizeKey = (supplier: string, number: string) => `${supplier.trim().toLowerCase()}::${number.trim().toLowerCase()}`;
export function checkInvoice(input: InvoiceInput, duplicate = false): CheckResult {
  const parsed = invoiceSchema.safeParse(input);
  if (!parsed.success) return { passed: false, expected_total: 0, checks: [{ code: 'schema', label: 'Required information', passed: false, detail: parsed.error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('; ') }] };
  const v = parsed.data;
  const expectedCents = v.items.reduce((sum, item) => sum + item.quantity * Math.round(item.unit_price * 100), 0) + Math.round(v.tax * 100);
  const expected = expectedCents / 100;
  const checks = [
    { code: 'required', label: 'Required information', passed: true, detail: 'Supplier, invoice number, dates and line items are present.' },
    { code: 'arithmetic', label: 'Line items & total', passed: expectedCents === Math.round(v.total * 100), detail: `Expected INR ${expected.toFixed(2)} including tax; submitted INR ${v.total.toFixed(2)}.` },
    { code: 'duplicate', label: 'Duplicate prevention', passed: !duplicate, detail: duplicate ? 'This supplier and invoice number already exist.' : 'No matching supplier and invoice number found.' },
    { code: 'dates', label: 'Date order', passed: v.due_date >= v.invoice_date, detail: v.due_date >= v.invoice_date ? 'Due date is on or after the invoice date.' : 'Due date cannot be earlier than invoice date.' },
    { code: 'amount_limit', label: 'Review amount limit', passed: expected <= 1000000, detail: expected <= 1000000 ? 'Within the INR 10,00,000 prototype review limit.' : 'Above the prototype limit; needs a separate finance review.' }
  ];
  return { passed: checks.every(c => c.passed), expected_total: expected, checks };
}
export function rulesSummary(result: CheckResult) {
  return result.passed ? 'All independent checks passed. Review the supplier and supporting business context before making a decision. No payment will be made by this application.' : `Review blocked: ${result.checks.filter(c => !c.passed).map(c => c.detail).join(' ')}`;
}
export function canReview(status: string, attempts: number) { return ['submitted', 'escalated'].includes(status) && attempts < limits.attempts; }
export function canDecide(role: string, status: string, passed: boolean, selfApproval = false) { return role === 'manager' && status === 'pending_approval' && passed && !selfApproval; }
