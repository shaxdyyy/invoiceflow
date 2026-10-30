import { z } from 'zod';
import { invoiceSchema } from '../checker';
import type { InvoiceInput } from '../types';
export const documentLimits = { maxBytes: 3 * 1024 * 1024, maxText: 24000, attempts: 2, dailyCalls: 10 };
export const acceptedTypes = ['application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain'];
export const documentAccept='.docx,.xlsx,.txt';
export function documentMime(name:string){const ext=name.toLowerCase().split('.').pop();return ext==='docx'?acceptedTypes[0]:ext==='xlsx'?acceptedTypes[1]:ext==='txt'?acceptedTypes[2]:'';}
export const extractedSchema = z.object({
 supplier:z.string().max(160).nullable(), invoice_number:z.string().max(80).nullable(),
 invoice_date:z.string().nullable(), due_date:z.string().nullable(), currency:z.string().max(12).nullable(),
 category:z.enum(['Office supplies','Software & services','Equipment','Travel','Other']),
 items:z.array(z.object({description:z.string().max(200),quantity:z.number().nullable(),unit_price:z.number().nullable()})).max(30),
 tax:z.number().nullable(),total:z.number().nullable(), notes:z.string().max(1500),
 po_number:z.string().max(80).nullable().optional(),
 uncertainties:z.array(z.string().max(300)).max(12)
});
export type Extracted = z.infer<typeof extractedSchema>;
export interface Extraction { data: Extracted; engine:'gemini'|'local-text'|'local-ocr'; text?:string; model?:string; documentId?:string; warnings:string[] }
export function validateDocument(name:string,type:string,size:number){
 if(size<=0)throw new Error('This file is empty. Choose an invoice with content.');
 if(size>documentLimits.maxBytes)throw new Error('Choose a document smaller than 3 MB.');
 const mime=documentMime(name);if(!mime||!['',mime,'application/octet-stream'].includes(type))throw new Error('Use DOCX, Excel (.xlsx), or TXT invoices only.');
 if(name.length>180)throw new Error('Shorten the filename to fewer than 180 characters.');
}
function readAmount(s:string|undefined):number|null {if(!s)return null;const v=Number(s.replace(/[,₹\s]/g,''));return Number.isFinite(v)&&v>=0?v:null;}
function date(value:string|undefined){if(!value)return null;const s=value.trim();const named=s.match(/^(\d{1,2})[- /]([A-Za-z]{3,9})[- /](\d{4})$/);if(named){const month=['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(named[2].slice(0,3).toLowerCase())+1;if(month)return `${named[3]}-${String(month).padStart(2,'0')}-${named[1].padStart(2,'0')}`;}if(/^\d{4}-\d{2}-\d{2}$/.test(s))return s;const m=s.match(/^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})$/);if(m)return `${m[3]}-${m[2].padStart(2,'0')}-${m[1].padStart(2,'0')}`;return null;}
export function parseInvoiceText(text:string):Extracted{
 const isLabel=(s:string)=>/^(?:supplier|vendor|from|issued by|invoice\s*(?:number|no\.?|#|date|total)|bill\s*(?:no\.?|number)|issue date|date|due date|payment due|currency|grand total|amount due|total(?: amount)?|(?:tax|gst|cgst|sgst|igst)(?: amount)?(?:\s*@\s*\d+(?:\.\d+)?%)?|(?:purchase order|po)(?:\s*(?:number|no\.?|#))?)\s*:?$/i.test(s);
 const normalized=text.slice(0,documentLimits.maxText).replace(/\r/g,'').split('\n').map(line=>{const cols=line.split(/\s*\|\s*|\t+|\s{2,}/).map(s=>s.trim()).filter(Boolean);if(cols.length>=2&&cols.length%2===0&&cols.every((c,i)=>i%2!==0||isLabel(c)))return cols.filter((_,i)=>i%2===0).map((label,i)=>label.replace(/:$/,'')+': '+cols[i*2+1]).join('\n');return line.replace(/ *\| */g,'  ').trimStart();}).join('\n');
 const field=(pattern:RegExp)=>normalized.match(pattern)?.[1]?.trim();
 const po_number=field(/^(?:purchase order|po)(?:\s*(?:number|no\.?|#))?\s*[:#]\s*(\S+)/im)||null;
 const supplier=field(/^(?:supplier|vendor|from|issued by)\s*[:\-]\s*(.+)$/im)||null;
 const invoice_number=field(/^(?:invoice\s*(?:number|no\.?|#)|bill\s*(?:no\.?|number))\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\-/_ .]{0,79}?)$/im)||null;
 const invoice_date=date(field(/^(?:invoice\s*date|issue\s*date|date)\s*[:\-]\s*([^\n]+)/im));
 const due_date=date(field(/^(?:due\s*date|payment due)\s*[:\-]\s*([^\n]+)/im));
 const total=readAmount(field(/^(?:grand\s*total|invoice\s*total|amount\s*due|total(?:\s*amount)?)\s*[:\-]?\s*(?:INR|Rs\.?|₹)?\s*([\d,]+(?:\.\d{1,2})?)\s*$/im));
 const taxMatches=[...normalized.matchAll(/^(?:tax|gst|cgst|sgst|igst)(?:\s*amount)?(?:\s*@\s*\d+(?:\.\d+)?%)?\s*[:\-]\s*(?:INR|Rs\.?|₹)?\s*([\d,]+(?:\.\d{1,2})?)\s*$/gim)];
 const explicitTax=readAmount(field(/^(?:tax|gst)(?:\s*amount)?\s*[:\-]\s*(?:INR|Rs\.?|₹)?\s*([\d,]+(?:\.\d{1,2})?)\s*$/im));
 const components=taxMatches.filter(m=>/^(?:cgst|sgst|igst)/i.test(m[0]));
 const componentTax=components.length?Math.round(components.reduce((s,m)=>s+(readAmount(m[1])||0),0)*100)/100:null;
 const tax=explicitTax??componentTax;
 const currency=/\b(?:USD|EUR|GBP|AED)\b|\$|€|£/.test(normalized)?(normalized.match(/\b(?:USD|EUR|GBP|AED)\b/)?.[0]||'NON-INR'):/\bINR\b|₹|\bRs\.?/.test(normalized)?'INR':null;
 const items:Extracted['items']=[];let descriptionColumn=0,quantityColumn=1,priceColumn=2;
 for(const line of normalized.split('\n')){
  const cols=line.split(/\s*\|\s*|\t+|\s{2,}/).map(s=>s.trim()).filter(Boolean);
  if(cols.some(c=>/^(?:qty|quantity)$/i.test(c))&&cols.some(c=>/^(?:unit price|rate|price)$/i.test(c))){descriptionColumn=Math.max(0,cols.findIndex(c=>/^(?:description|item|item description)$/i.test(c)));quantityColumn=cols.findIndex(c=>/^(?:qty|quantity)$/i.test(c));priceColumn=cols.findIndex(c=>/^(?:unit price|rate|price)$/i.test(c));continue;}
  if(cols.length>Math.max(descriptionColumn,quantityColumn,priceColumn)&&!/^(?:item|description|subtotal|total|tax|gst|cgst|sgst|igst|quantity|qty|invoice|supplier|vendor|due|currency)/i.test(cols[0])){
   const quantity=readAmount(cols[quantityColumn]);const price=readAmount(cols[priceColumn].replace(/^(?:INR|Rs\.?)\s*/i,''));
   if(quantity!==null&&Number.isInteger(quantity)&&quantity>0&&price!==null)items.push({description:cols[descriptionColumn].slice(0,200),quantity,unit_price:price});
  }
 }
 const uncertainties:string[]=[];
 if(items.length>30)uncertainties.push('More than 30 line items found. Split the invoice or reconcile all items before saving.');
 if([...normalized.matchAll(/^(?:invoice\s*(?:number|no\.?|#)|bill\s*(?:no\.?|number))\s*[:#\-]/gim)].length>1)uncertainties.push('Multiple invoice references found. Upload only one invoice per file.');
 if(explicitTax!==null&&componentTax!==null&&explicitTax!==componentTax)uncertainties.push('The printed tax total and tax components disagree.');
 if(!supplier)uncertainties.push('Supplier label was not found.');if(!invoice_number)uncertainties.push('Invoice number was not found.');
 if(!invoice_date)uncertainties.push('Invoice date could not be read.');if(!due_date)uncertainties.push('Due date is not stated or could not be read.');
 if(!items.length)uncertainties.push('Line items need confirmation.');if(tax===null)uncertainties.push('Tax amount is not explicitly stated.');if(total===null)uncertainties.push('Invoice total could not be read.');
 if(currency!=='INR')uncertainties.push(currency?'This document is not in INR.':'Currency is not explicitly stated. Confirm INR before saving.');
 return {po_number,supplier,invoice_number,invoice_date,due_date,currency,category:'Other',items:items.slice(0,30),tax,total,notes:'',uncertainties};
}
export function toInvoiceInput(data:Extracted):{input:InvoiceInput|null;missing:string[]}{
 const parsed=invoiceSchema.safeParse({...data,notes:data.notes||''});
 const missing=parsed.success?[]:parsed.error.issues.map(i=>`${i.path.join('.')}: ${i.message}`);
 if(data.currency!=='INR')missing.push('Currency must be confirmed as INR.');
 if(data.uncertainties.length)missing.push(...data.uncertainties);
 return {input:parsed.success&&data.currency==='INR'&&data.uncertainties.length===0?parsed.data:null,missing:[...new Set(missing)]};
}
