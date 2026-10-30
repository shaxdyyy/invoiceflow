import { checkInvoice, canDecide, canReview, normalizeKey } from './checker';
import type { InvoiceInput } from './types';
export const validFixture: InvoiceInput = { supplier:'Paper & Co.',invoice_number:'TEST-001',invoice_date:'2026-10-01',due_date:'2026-10-15',category:'Office supplies',items:[{description:'Notebook',quantity:10,unit_price:50}],tax:0,total:500,notes:'' };
export function runScenarios() {
  const tests: {name:string;expected:string;run:()=>boolean}[] = [
    {name:'Valid invoice',expected:'Pass all independent checks',run:()=>checkInvoice(validFixture).passed},
    {name:'Incorrect total',expected:'Block a INR 200 mismatch',run:()=>!checkInvoice({...validFixture,total:700}).passed},
    {name:'Missing supplier',expected:'Reject incomplete input',run:()=>!checkInvoice({...validFixture,supplier:''}).passed},
    {name:'Duplicate invoice',expected:'Block repeated supplier + number',run:()=>!checkInvoice(validFixture,true).passed},
    {name:'Date order',expected:'Block due date before issue date',run:()=>!checkInvoice({...validFixture,due_date:'2026-09-01'}).passed},
    {name:'Money precision',expected:'Handle 3 × 0.10 exactly',run:()=>checkInvoice({...validFixture,items:[{description:'Small item',quantity:3,unit_price:0.1}],total:0.3}).passed},
    {name:'Retry limit',expected:'Stop after two review attempts',run:()=>!canReview('escalated',2)},
    {name:'Bounded retry',expected:'Allow remaining attempt after failure',run:()=>canReview('escalated',1)},
    {name:'Already completed / no-op',expected:'Do not review an approved invoice again',run:()=>!canReview('approved',1)},
    {name:'Approval permissions',expected:'Employee cannot approve',run:()=>!canDecide('employee','pending_approval',true)},
    {name:'Single-manager approval',expected:'One manager may approve a checked invoice, including their own upload',run:()=>canDecide('manager','pending_approval',true,true)},
    {name:'Failed success gate',expected:'Manager cannot override failed checks',run:()=>!canDecide('manager','pending_approval',false)},
    {name:'Amount limit',expected:'Escalate values outside prototype policy',run:()=>!checkInvoice({...validFixture,items:[{description:'Equipment',quantity:1,unit_price:1000001}],total:1000001}).passed},
    {name:'Normalized duplicate key',expected:'Ignore letter case and surrounding spaces',run:()=>normalizeKey(' Paper & Co. ',' TEST-001 ')===normalizeKey(validFixture.supplier,validFixture.invoice_number)}
  ];
  return tests.map(t=>{const start=performance.now();try{return {name:t.name,expected:t.expected,passed:t.run(),ms:Math.round((performance.now()-start)*100)/100};}catch{return {name:t.name,expected:t.expected,passed:false,ms:0};}});
}
