import { parseInvoiceText, validateDocument, type Extraction } from './parser';
import { officeText } from './office';
export async function readDocumentLocally(file:File,onProgress:(message:string)=>void,signal?:AbortSignal):Promise<Extraction>{
 if(signal?.aborted)throw new Error('Reading cancelled');validateDocument(file.name,file.type,file.size);
 onProgress('Reading invoice text and tables…');const text=await officeText(new Uint8Array(await file.arrayBuffer()),file.name);
 if(signal?.aborted)throw new Error('Reading cancelled');
 return {data:parseInvoiceText(text),engine:'local-text',text,warnings:[]};
}
