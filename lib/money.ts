// Monetary checks use integer paise. Never ask a language model to calculate money.
export function paise(value:number):bigint {
 if(!Number.isFinite(value)||value<0)throw new Error('Invalid monetary value');
 const match=/^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
 if(!match)throw new Error('Use at most two decimal places');
 return BigInt(match[1])*100n+BigInt((match[2]||'').padEnd(2,'0'));
}
export function formatPaise(value:bigint){return `${value/100n}.${String(value%100n).padStart(2,'0')}`;}
export function calculateInvoice(items:{quantity:number;unit_price:number}[],tax:number){
 const lines=items.map(i=>{if(!Number.isSafeInteger(i.quantity)||i.quantity<1||i.quantity>100000)throw new Error('Quantity must be a whole number from 1 to 100,000');return BigInt(i.quantity)*paise(i.unit_price);});
 const subtotal=lines.reduce((a,b)=>a+b,0n),taxPaise=paise(tax);
 return {lines,subtotal,tax:taxPaise,total:subtotal+taxPaise};
}
