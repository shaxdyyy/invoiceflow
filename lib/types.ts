export type Status = 'submitted' | 'processing' | 'needs_correction' | 'pending_approval' | 'approved' | 'rejected' | 'escalated';
export type Role = 'employee' | 'manager';
export interface LineItem { description: string; quantity: number; unit_price: number }
export interface InvoiceInput {
  supplier: string; invoice_number: string; invoice_date: string; due_date: string;
  category: string; items: LineItem[]; tax: number; total: number; notes: string;
}
export interface Check { code: string; label: string; passed: boolean; detail: string }
export interface CheckResult { passed: boolean; expected_total: number; checks: Check[] }
export interface Invoice extends InvoiceInput {
  id: string; created_at: string; updated_at: string; created_by: string;
  status: Status; attempts: number; checks: CheckResult | null;
  review_summary: string | null; review_mode: 'rules' | 'ai' | null;
  model_tokens: number; decision_note: string | null; decided_by: string | null;
  run_id: string | null;
}
export interface Activity {
  id: string; invoice_id: string; actor_id: string; event: string;
  details: Record<string, unknown>; created_at: string;
}
export const STATUS_LABELS: Record<Status, string> = {
  submitted: 'Ready for review', processing: 'Reviewing', needs_correction: 'Needs correction',
  pending_approval: 'Awaiting approval', approved: 'Approved', rejected: 'Rejected', escalated: 'Escalated'
};
export const CATEGORIES = ['Office supplies', 'Software & services', 'Equipment', 'Travel', 'Other'];
export const money = (value: number) => new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 }).format(value);
export const dateLabel = (value: string) => new Date(value).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
