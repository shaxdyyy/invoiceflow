import type {Extracted} from './documents/parser';

export const demoInvoiceFixtures={
 'office-01':{
  filename:'invoiceflow-practice-office-01.pdf',
  sha256:'7f4ec6cd79f7ed55f6514867217d4528ffac06a6887952e27cebae006bfdd5ea',
  data:{supplier:'BluePeak Office Supplies Pvt Ltd',invoice_number:'BP-INV-2026-041',invoice_date:'2026-10-28',due_date:'2026-11-27',currency:'INR',category:'Office supplies',items:[{description:'A4 copy paper, 75 GSM (ream)',quantity:8,unit_price:325},{description:'Blue ballpoint pens (box of 10)',quantity:6,unit_price:180},{description:'A4 file folders (pack)',quantity:4,unit_price:62.5}],tax:707.4,total:4637.4,notes:'Fictional practice invoice. No payment is due.',uncertainties:[]} satisfies Extracted,
 },
 'software-02':{
  filename:'invoiceflow-practice-software-02.pdf',
  sha256:'f6eb57fd1b38d1cbea462cebfddad0d079e7ee53b43e846d4398add2d10f2065',
  data:{supplier:'GreenTrail IT Services LLP',invoice_number:'GT-INV-2026-188',invoice_date:'2026-10-21',due_date:'2026-11-15',currency:'INR',category:'Software & services',items:[{description:'Cloud backup annual plan (user licence)',quantity:2,unit_price:4500},{description:'Data migration service (one-time)',quantity:1,unit_price:1200}],tax:1836,total:12036,notes:'Fictional practice invoice. No payment is due.',uncertainties:[]} satisfies Extracted,
 },
} as const;
export type DemoInvoiceFixtureId=keyof typeof demoInvoiceFixtures;
export function demoInvoiceFixture(id:DemoInvoiceFixtureId){return demoInvoiceFixtures[id];}
export function findDemoInvoiceFixture(hash:string){return (Object.entries(demoInvoiceFixtures) as [DemoInvoiceFixtureId,(typeof demoInvoiceFixtures)[DemoInvoiceFixtureId]][]).find(([,fixture])=>fixture.sha256===hash)?.[0]||null;}
