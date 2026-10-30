import {documentLimits} from './parser';
export async function pdfText(bytes:Uint8Array):Promise<string>{
 if(new TextDecoder('latin1').decode(bytes.slice(0,5))!=='%PDF-')throw new Error('This is not a valid PDF document.');
 // PDF.js parses content without executing document JavaScript or external links.
 const pdfjs=await import('pdfjs-dist/legacy/build/pdf.mjs');
 if(typeof window!=='undefined')pdfjs.GlobalWorkerOptions.workerSrc='/pdf.worker.min.mjs';
 const task=pdfjs.getDocument({data:bytes.slice(),useSystemFonts:true,stopAtErrors:true,useWorkerFetch:false});
 try{const pdf=await task.promise;if(pdf.numPages>20)throw new Error('Use a PDF with at most 20 pages.');
 if(await pdf.getJSActions()||await pdf.getAttachments())throw new Error('PDF scripts or attachments are not allowed. Export a plain invoice PDF.');
 const lines:string[]=[];let length=0;
 for(let i=1;i<=pdf.numPages;i++){const page=await pdf.getPage(i);const actions=await page.getJSActions();if(actions)throw new Error('PDF scripts are not allowed.');const annotations=await page.getAnnotations();if(annotations.some(a=>a.actions||['FileAttachment','RichMedia','Screen'].includes(a.subtype)))throw new Error('Active PDF content is not allowed.');const content=await page.getTextContent();let row='',lastY:number|undefined,lastEnd=0;
 for(const item of content.items){if(!('str' in item))continue;const y=item.transform[5],x=item.transform[4];if(lastY!==undefined&&Math.abs(y-lastY)>3){lines.push(row);row='';lastEnd=0;}if(row&&x-lastEnd>9)row+='  ';else if(row&&!row.endsWith(' '))row+=' ';row+=item.str;lastY=y;lastEnd=x+item.width;length+=item.str.length;if(length>documentLimits.maxText)throw new Error('Use a PDF with fewer than 24,000 text characters.');if(item.hasEOL){lines.push(row);row='';lastY=undefined;}}
 if(row)lines.push(row);page.cleanup();}
 const text=lines.join('\n');if(text.length>documentLimits.maxText)throw new Error('PDF text is too long.');return text;
 }catch(e){if((e as Error).name==='PasswordException')throw new Error('Password-protected PDFs are not supported. Export an unlocked invoice PDF.');throw e;}finally{await task.destroy();}
}
