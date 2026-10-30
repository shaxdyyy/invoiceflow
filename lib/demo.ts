import { checkInvoice, normalizeKey, rulesSummary } from './checker';
import type { Invoice, InvoiceInput, Activity, Status } from './types';
const ago = (days: number) => new Date(Date.now() - days * 86400000).toISOString();
export function sampleInput(): InvoiceInput {
  const today = new Date().toISOString().slice(0,10);
  return { supplier: '', invoice_number: '', invoice_date: today, due_date: today, category: 'Office supplies', items: [{ description: '', quantity: 1, unit_price: 0 }], tax: 0, total: 0, notes: '' };
}
export function demoInvoice(input: InvoiceInput, status: Status = 'submitted', days = 0): Invoice {
  const checked = ['pending_approval','approved','rejected','needs_correction'].includes(status);
  const checks = checked ? checkInvoice(input) : null;
  return { ...input, id: crypto.randomUUID(), created_by: 'demo-employee', created_at: ago(days), updated_at: ago(days), status, attempts: checked ? 1 : 0, checks, review_summary: checks ? rulesSummary(checks) : null, review_mode: checked ? 'rules' : null, model_tokens: 0, decision_note: status === 'approved' ? 'Verified the order and supplier details.' : status === 'rejected' ? 'Order was cancelled by the requesting team.' : null, decided_by: ['approved','rejected'].includes(status) ? 'demo-manager' : null, run_id: null };
}
export function seedDemo(): { invoices: Invoice[]; activities: Activity[] } {
  const make = (supplier: string, number: string, desc: string, qty: number, price: number, tax: number, status: Status, days: number, wrong?: number) => demoInvoice({ ...sampleInput(), supplier, invoice_number: number, items: [{description: desc, quantity: qty, unit_price: price}], tax, total: wrong ?? qty*price+tax, invoice_date: ago(days+1).slice(0,10), due_date: ago(-7).slice(0,10), category: desc.includes('subscription') ? 'Software & services' : 'Office supplies' },status,days);
  const invoices = [
    make('Notion Labs','INV-2026-104','Team workspace subscription',12,800,1728,'pending_approval',0),
    make('Paper & Co.','INV-2026-103','A5 notebooks',10,50,0,'needs_correction',0,700),
    make('Linear Technologies','INV-2026-102','Project management subscription',8,650,936,'approved',1),
    make('Studio Supply','INV-2026-101','Desk essentials kit',6,1200,1296,'pending_approval',1),
    make('Bright Office','INV-2026-100','Whiteboard markers',20,45,162,'submitted',2),
    make('Cloudspace','INV-2026-099','Storage subscription',1,2400,432,'approved',3),
    make('Everyday Goods','INV-2026-098','Printer paper boxes',4,950,684,'approved',4),
    make('Northstar Supplies','INV-2026-097','Desk organizers',5,450,405,'rejected',5)
  ];
  const activities: Activity[] = invoices.flatMap(i => [
    { id: crypto.randomUUID(),invoice_id:i.id,actor_id:i.created_by,event:'invoice_submitted',details:{supplier:i.supplier},created_at:i.created_at },
    ...(i.checks ? [{id:crypto.randomUUID(),invoice_id:i.id,actor_id:'demo-employee',event:'review_completed',details:{checks:i.checks,mode:'rules',status:i.status},created_at:i.updated_at}] : []),
    ...(i.decided_by ? [{id:crypto.randomUUID(),invoice_id:i.id,actor_id:i.decided_by,event:'invoice_'+i.status,details:{reason:i.decision_note},created_at:i.updated_at}] : [])
  ]);
  return { invoices, activities };
}
export function isDuplicate(invoices: Invoice[], input: InvoiceInput, exclude?: string) { return invoices.some(i=>i.id!==exclude && normalizeKey(i.supplier,i.invoice_number)===normalizeKey(input.supplier,input.invoice_number)); }
