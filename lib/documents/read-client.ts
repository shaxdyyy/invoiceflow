import { parseInvoiceText, validateDocument, documentLimits, type Extraction } from './parser';
export async function readDocumentLocally(file:File,onProgress:(message:string)=>void):Promise<Extraction>{
 validateDocument(file.name,file.type,file.size);let text='';let ocr=false;
 if(file.type==='text/plain'){text=await file.text();}
 else if(file.type==='application/pdf'){
  onProgress('Reading the PDF…');
  const pdfjs=await import('pdfjs-dist');
  pdfjs.GlobalWorkerOptions.workerSrc=new URL('pdfjs-dist/build/pdf.worker.min.mjs',import.meta.url).toString();
  const loading=pdfjs.getDocument({data:new Uint8Array(await file.arrayBuffer())});const pdf=await loading.promise;
  try{
   if(pdf.numPages>documentLimits.maxPages)throw new Error('Use a PDF with 10 pages or fewer.');
   const pages:string[]=[];let worker:Awaited<ReturnType<typeof import('tesseract.js')['createWorker']>>|undefined;
   try{for(let p=1;p<=pdf.numPages;p++){
    onProgress(`Reading page ${p} of ${pdf.numPages}…`);const page=await pdf.getPage(p);const content=await page.getTextContent();
    let pageText='';let previousY:number|null=null;
    for(const item of content.items){if(!('str' in item))continue;const y=item.transform[5];if(previousY!==null&&Math.abs(previousY-y)>3)pageText+='\n';else if(pageText&&!pageText.endsWith('\n'))pageText+='  ';pageText+=item.str;previousY=y;if(item.hasEOL)pageText+='\n';}
    if(pageText.replace(/\s/g,'').length<20){
     ocr=true;onProgress(`Reading scanned page ${p} on your device…`);const viewport=page.getViewport({scale:1.6});const canvas=document.createElement('canvas');canvas.width=viewport.width;canvas.height=viewport.height;
     await page.render({canvas,viewport}).promise;
     worker??=await (await import('tesseract.js')).createWorker('eng');const result=await worker.recognize(canvas);pageText=result.data.text;
    }
    pages.push(pageText);if(pages.join('').length>documentLimits.maxText)throw new Error('This invoice has too much text. Use a smaller document.');
   }}finally{await worker?.terminate();}
   text=pages.join('\n');
  }finally{await loading.destroy();}
 }else{
  ocr=true;onProgress('Reading the image on your device…');const {createWorker}=await import('tesseract.js');const worker=await createWorker('eng');
  try{text=(await worker.recognize(file)).data.text;}finally{await worker.terminate();}
 }
 if(!text.trim())throw new Error('No readable text was found. Try a clearer document or enter details manually.');
 return {data:parseInvoiceText(text),engine:ocr?'local-ocr':'local-text',text:text.slice(0,documentLimits.maxText),warnings:ocr?['Local OCR can misread characters. Check uncertain fields against the original.']:[]};
}
