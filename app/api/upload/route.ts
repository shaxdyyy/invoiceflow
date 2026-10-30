import {NextRequest,NextResponse} from 'next/server';
import {randomUUID} from 'node:crypto';
import {authenticated} from '@/lib/server-auth';
import {documentMime,validateDocument} from '@/lib/documents/parser';
import {inspectDocument} from '@/lib/documents/read-server';
export const runtime='nodejs';export const maxDuration=60;
export async function POST(req:NextRequest){
 try{const {db,user}=await authenticated(req);
 if(Number(req.headers.get('content-length')||0)>3*1024*1024+20000)throw new Error('Choose an invoice smaller than 3 MB.');
 const quota=await db.rpc('reserve_upload');if(quota.error)throw quota.error;
 const form=await req.formData(),file=form.get('file');if(!(file instanceof File))throw new Error('Choose one invoice file.');
 validateDocument(file.name,file.type,file.size);const bytes=new Uint8Array(await file.arrayBuffer());
 await inspectDocument(bytes,file.name,documentMime(file.name));
 const path=`${user.id}/${randomUUID()}/${file.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;
 const uploaded=await db.storage.from('invoice-documents').upload(path,bytes,{contentType:documentMime(file.name),upsert:false,cacheControl:'0'});if(uploaded.error)throw new Error('Could not store the original privately.');
 const saved=await db.rpc('register_validated_document',{p_path:path,p_name:file.name,p_mime:documentMime(file.name),p_size:bytes.length,p_secret:process.env.REVIEW_SERVER_SECRET});
 if(saved.error){await db.storage.from('invoice-documents').remove([path]);throw saved.error;}
 return NextResponse.json({document:saved.data});
 }catch(e){return NextResponse.json({error:(e as Error).message||'Upload could not finish.'},{status:400});}
}
