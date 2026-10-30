import { checkInvoice } from './checker';
import type { Invoice } from './types';
export interface PurchaseOrder {id?:string;reference:string;supplier:string;receipt_reference:string;items:{description:string;quantity:number;unit_price:number;received:number}[]}
export interface Assessment {score:number;level:'Low'|'Medium'|'High';blocked:boolean;signals:{code:string;points:number;blocking:boolean;detail:string;next_action:string}[];matching:{label:string;passed:boolean;detail:string}[];matching_mode:string;history_count:number;assessed_at:string}
export const normalize=(v:string)=>v.toLowerCase().replace(/[^a-z0-9]/g,'');
export function demoAssessment(invoice:Invoice,all:Invoice[],orders:PurchaseOrder[]):Assessment{
 const signals:Assessment['signals']=[];const matching:Assessment['matching']=[];
 const check=checkInvoice(invoice);for(const c of check.checks.filter(c=>!c.passed))signals.push({code:c.code,points:60,blocking:true,detail:c.detail,next_action:'Check the source and request corrected details. Never silently change the printed amount.'});
 const others=all.filter(i=>i.id!==invoice.id&&i.status!=='rejected'&&normalize(i.supplier)===normalize(invoice.supplier));
 const signature=(i:Invoice)=>JSON.stringify(i.items.map(v=>[v.description.trim().toLowerCase(),v.quantity,v.unit_price]).sort());
 if(others.some(i=>normalize(i.invoice_number)===normalize(invoice.invoice_number)))signals.push({code:'duplicate_number',points:95,blocking:true,detail:'Supplier and invoice number match after removing punctuation and spaces.',next_action:'Investigate both submissions and reject the duplicate.'});
 else if(others.some(i=>i.total===invoice.total&&i.invoice_date===invoice.invoice_date&&signature(i)===signature(invoice)))signals.push({code:'duplicate_content',points:80,blocking:true,detail:'Supplier, date, amount and line items match another submission. Possible duplicate, not proof of fraud.',next_action:'Compare originals and reject the duplicate or correct the wrongly entered record.'});
 const history=others.filter(i=>i.status==='approved').map(i=>i.total).sort((a,b)=>a-b);const median=history.length%2?history[Math.floor(history.length/2)]:(history[history.length/2-1]+history[history.length/2])/2;
 if(history.length>=5&&median>0&&invoice.total>median*3)signals.push({code:'amount_outlier',points:35,blocking:false,detail:'Amount exceeds three times this supplier’s median approved invoice.',next_action:'Confirm the unusual purchase against supporting documents.'});
 if(invoice.invoice_date>new Date(Date.now()+86400000).toISOString().slice(0,10))signals.push({code:'future_date',points:20,blocking:false,detail:'Invoice date is in the future.',next_action:'Confirm the issue date.'});
 const mode=invoice.matching_mode||'none';
 if(mode==='none')matching.push({label:'Supporting documents',passed:false,detail:'Select a purchase order to enable matching.'});else{
 const po=orders.find(o=>o.reference===invoice.purchase_order_number);
 if(!po)matching.push({label:'Purchase order exists',passed:false,detail:'No saved purchase order matches this reference.'});else{
 matching.push({label:'Supplier matches',passed:normalize(po.supplier)===normalize(invoice.supplier),detail:'Compare invoice and purchase order supplier.'});
 const grouped=new Map<string,{quantity:number;prices:number[]}>();for(const item of invoice.items){const key=item.description.trim().toLowerCase();const g=grouped.get(key)||{quantity:0,prices:[]};g.quantity+=item.quantity;g.prices.push(item.unit_price);grouped.set(key,g);}
 for(const [desc,item] of grouped){const ordered=po.items.find(o=>o.description.trim().toLowerCase()===desc);const used=all.filter(i=>i.id!==invoice.id&&i.status==='approved'&&i.purchase_order_number===po.reference).flatMap(i=>i.items).filter(i=>i.description.trim().toLowerCase()===desc).reduce((s,i)=>s+i.quantity,0);
 matching.push({label:desc+' · order quantity and price',passed:!!ordered&&item.quantity+used<=ordered.quantity&&item.prices.every(p=>p===ordered.unit_price),detail:`Current ${item.quantity}; previously approved ${used}; ordered ${ordered?.quantity??'not found'}. Prices must match exactly.`});
 if(mode==='three_way')matching.push({label:desc+' · goods received',passed:!!ordered&&item.quantity+used<=ordered.received&&!!po.receipt_reference,detail:`Received ${ordered?.received||0}; receipt ${po.receipt_reference||'missing'}.`});
 }}if(matching.some(m=>!m.passed))signals.push({code:'matching_exception',points:60,blocking:true,detail:'Purchase order or receipt matching failed.',next_action:'Ask the manager to verify quantities, prices and the goods receipt, then check again.'});}
 const score=Math.min(100,signals.reduce((s,v)=>s+v.points,0));return {score,level:score>=60?'High':score>=25?'Medium':'Low',blocked:signals.some(s=>s.blocking),signals,matching,matching_mode:mode,history_count:history.length,assessed_at:new Date().toISOString()};
}
