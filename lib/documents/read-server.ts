import sharp from 'sharp';
import {officeText} from './office';
import {pdfText} from './pdf';
import {validateDocument,documentMime} from './parser';
export async function inspectDocument(bytes:Uint8Array,name:string,mime:string){
 validateDocument(name,mime,bytes.length);
 const type=documentMime(name);
 if(type==='application/pdf')return {text:await pdfText(bytes),visual:true};
 if(type==='image/jpeg'){
  if(bytes[0]!==0xff||bytes[1]!==0xd8||bytes[2]!==0xff)throw new Error('This is not a valid JPG image.');
  const image=sharp(bytes,{limitInputPixels:25000000,failOn:'warning'});const meta=await image.metadata();
  if(meta.format!=='jpeg'||!meta.width||!meta.height||meta.width<40||meta.height<40)throw new Error('Use a readable JPG invoice.');
  await image.resize({width:2400,height:2400,fit:'inside',withoutEnlargement:true}).jpeg().toBuffer();
  return {text:'',visual:true};
 }
 return {text:await officeText(bytes,name),visual:false};
}
