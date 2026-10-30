import {NextRequest} from 'next/server';
import {z} from 'zod';
import {authenticated} from '@/lib/server-auth';
export const runtime='nodejs';
export async function GET(req:NextRequest){try{
 const {db}=await authenticated(req);const id=z.uuid().parse(req.nextUrl.searchParams.get('id'));
 const found=await db.from('documents').select('id,storage_path,filename,mime_type').eq('id',id).single();
 if(found.error||!found.data)return Response.json({error:'Document not accessible.'},{status:404});
 const file=await db.storage.from('invoice-documents').download(found.data.storage_path);if(file.error||!file.data)throw new Error('Document unavailable.');
 const logged=await db.rpc('record_document_access',{p_id:id});if(logged.error)throw new Error('Could not record document access.');
 const name=found.data.filename.replace(/[^a-zA-Z0-9._-]/g,'_');
 return new Response(await file.data.arrayBuffer(),{headers:{'Content-Type':found.data.mime_type,'Content-Disposition':`attachment; filename="${name}"`,'Cache-Control':'private, no-store, max-age=0','X-Content-Type-Options':'nosniff','Content-Security-Policy':"sandbox; default-src 'none'"}});
 }catch{return Response.json({error:'Sign in to the company workspace to open this document.'},{status:403,headers:{'Cache-Control':'no-store'}});}}
