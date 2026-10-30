import { parseInvoiceText, validateDocument, type Extraction } from './parser';
import { officeText } from './office';
export async function readDocumentLocally(file:File,onProgress:(message:string)=>void,signal?:AbortSignal):Promise<Extraction>{
 if(signal?.aborted)throw new Error('Reading cancelled');validateDocument(file.name,file.type,file.size);
 onProgress('Reading invoice text and tables…');const bytes=new Uint8Array(await file.arrayBuffer());let text='';if(file.name.toLowerCase().endsWith('.pdf'))text=await (await import('./pdf')).pdfText(bytes);else if(/\.jpe?g$/i.test(file.name)){if(bytes[0]!==0xff||bytes[1]!==0xd8)throw new Error('This is not a JPG invoice.');return {data:{...parseInvoiceText(''),uncertainties:['Demo mode does not send documents to AI. Use the live workspace with company-approved Gemini for JPG/scanned invoices.']},engine:'local-text',text:'',warnings:[]};}else text=await officeText(bytes,file.name);
 if(signal?.aborted)throw new Error('Reading cancelled');
 return {data:parseInvoiceText(text),engine:'local-text',text,warnings:[]};
}
