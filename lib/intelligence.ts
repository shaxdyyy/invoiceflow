import { checkInvoice } from './checker';
import type { Invoice } from './types';
export interface Assessment {score:number;level:'Low'|'Medium'|'High';blocked:boolean;signals:{code:string;points:number;blocking:boolean;detail:string;next_action:string}[];history_count:number;assessed_at:string}
export const normalize=(v:string)=>v.toLowerCase().replace(/[^a-z0-9]/g,'');
export function demoAssessment(invoice:Invoice,all:Invoice[]):Assessment{
 const signals:Assessment['signals']=[];
 const check=checkInvoice(invoice);for(const c of check.checks.filter(c=>!c.passed))signals.push({code:c.code,points:60,blocking:true,detail:c.detail,next_action:'Check the source and request corrected details. Never silently change the printed amount.'});
 const others=all.filter(i=>i.id!==invoice.id&&i.status!=='rejected'&&normalize(i.supplier)===normalize(invoice.supplier));
 const signature=(i:Invoice)=>JSON.stringify(i.items.map(v=>[v.description.trim().toLowerCase(),v.quantity,v.unit_price]).sort());
 if(others.some(i=>normalize(i.invoice_number)===normalize(invoice.invoice_number)))signals.push({code:'duplicate_number',points:95,blocking:true,detail:'Supplier and invoice number match after removing punctuation and spaces.',next_action:'Investigate both submissions and reject the duplicate.'});
 else if(others.some(i=>i.total===invoice.total&&i.invoice_date===invoice.invoice_date&&signature(i)===signature(invoice)))signals.push({code:'duplicate_content',points:80,blocking:true,detail:'Supplier, date, amount and line items match another submission. Possible duplicate, not proof of fraud.',next_action:'Compare originals and reject the duplicate or correct the wrongly entered record.'});
 const history=others.filter(i=>i.status==='approved').map(i=>i.total).sort((a,b)=>a-b);const median=history.length%2?history[Math.floor(history.length/2)]:(history[history.length/2-1]+history[history.length/2])/2;
 if(history.length>=5&&median>0&&invoice.total>median*3)signals.push({code:'amount_outlier',points:35,blocking:false,detail:'Amount exceeds three times this supplier’s median approved invoice.',next_action:'Confirm the unusual purchase against supporting documents.'});
 if(invoice.invoice_date>new Date(Date.now()+86400000).toISOString().slice(0,10))signals.push({code:'future_date',points:20,blocking:false,detail:'Invoice date is in the future.',next_action:'Confirm the issue date.'});
 const score=Math.min(100,signals.reduce((s,v)=>s+v.points,0));return {score,level:score>=60?'High':score>=25?'Medium':'Low',blocked:signals.some(s=>s.blocking),signals,history_count:history.length,assessed_at:new Date().toISOString()};
}
