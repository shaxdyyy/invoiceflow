import { unzipSync, strFromU8 } from 'fflate';
import { XMLParser } from 'fast-xml-parser';
import { documentLimits, documentMime } from './parser';
// Inspect the ZIP directory before decompression. Never render Office HTML or execute macros/formulas.
export function inspectOfficeZip(bytes:Uint8Array){
 let expanded=0,entries=0;
 const files=unzipSync(bytes,{filter:entry=>{expanded+=entry.originalSize;entries++;if(expanded>16*1024*1024||entries>1500)throw new Error('Office document is too complex. Use a smaller file.');if(/(?:^|\/)(?:vbaProject\.bin|embeddings|activeX)(?:\/|$)|\.exe$/i.test(entry.name))throw new Error('Embedded programs and macros are not allowed.');return entry.name==='word/document.xml'||entry.name.endsWith('.rels')||entry.name==='[Content_Types].xml';}});
 for(const [name,content] of Object.entries(files))if(name!=='word/document.xml'&&/vbaProject|oleObject|activeX|attachedTemplate|TargetMode\s*=\s*["']External/i.test(strFromU8(content)))throw new Error('Remove macros, embedded objects or external relationships before uploading.');
 return files;
}
export async function officeText(bytes:Uint8Array,name:string):Promise<string>{
 const type=documentMime(name);let text='';
 if(type==='text/plain'){text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);if(text.includes('\0'))throw new Error('Not a valid text invoice.');}
 else {
  if(bytes[0]!==80||bytes[1]!==75)throw new Error('This is not a valid Office document.');
  const zip=inspectOfficeZip(bytes);
  if(name.toLowerCase().endsWith('.docx')){
   if(!zip['word/document.xml'])throw new Error('Invalid DOCX document.');
   const xml=strFromU8(zip['word/document.xml']);if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('Unsupported document XML.');
   const tree=new XMLParser({preserveOrder:true,ignoreAttributes:true,processEntities:true,parseTagValue:false}).parse(xml);
   function read(nodes:Record<string,unknown>[]):string{return nodes.map(node=>Object.entries(node).map(([tag,value])=>{if(tag==='#text')return String(value);const inner=Array.isArray(value)?read(value):'';if(tag==='w:tc')return inner.replace(/\n/g,' ').trim()+' | ';if(tag==='w:tr')return inner.replace(/\s*\|\s*$/,'')+'\n';return inner+(tag==='w:p'?'\n':tag==='w:tab'?'  ':'');}).join('')).join('');}
   text=read(tree);
  }else{
   const ExcelJS=(await import('exceljs')).default;const workbook=new ExcelJS.Workbook();await workbook.xlsx.load(bytes as never);
   if(workbook.worksheets.length>5)throw new Error('Use an Excel file with at most 5 worksheets.');
   const rows:string[]=[];let count=0;
   for(const sheet of workbook.worksheets){sheet.eachRow(row=>{if(++count>500||row.cellCount>40)throw new Error('Use at most 500 rows and 40 columns.');const cells:string[]=[];row.eachCell({includeEmpty:true},cell=>{if(cell.type===ExcelJS.ValueType.Formula)throw new Error('Replace Excel formulas with values before uploading. This preserves the printed figures.');cells.push(cell.value instanceof Date?cell.value.toISOString().slice(0,10):cell.text);});rows.push(cells.join(' | '));});}
   text=rows.join('\n');
  }
 }
 if(text.length>documentLimits.maxText)throw new Error('Use a document with fewer than 24,000 text characters.');
 if(!text.trim())throw new Error('No readable text found. Use a document containing invoice text and tables.');
 return text;
}
