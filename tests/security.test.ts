import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {checkInvoice,invoiceSchema} from '../lib/checker';
import {calculateInvoice,formatPaise,paise} from '../lib/money';
import {validFixture} from '../lib/scenarios';
import {validateDocument,documentMime} from '../lib/documents/parser';
import {officeText} from '../lib/documents/office';
import {zipSync,strToU8} from 'fflate';
import {inspectDocument} from '../lib/documents/read-server';
import {testPdf} from './pdf-fixture';
import sharp from 'sharp';
import {parseInvoiceText} from '../lib/documents/parser';
test('exact independent money calculations, including decimal edge cases',()=>{
 assert.equal(formatPaise(calculateInvoice([{quantity:3,unit_price:0.1}],0.2).total),'0.50');
 assert.equal(formatPaise(calculateInvoice([{quantity:100000,unit_price:99999999.99}],0.01).total),'9999999999000.01');
 assert.equal(paise(1.01),101n);assert.throws(()=>paise(1.001));assert.throws(()=>paise(NaN));assert.throws(()=>paise(-1));
 assert.equal(invoiceSchema.safeParse({...validFixture,tax:0.000000001}).success,false);
 for(let i=1;i<=500;i++){const cents=(i*7919)%999999;const value=Number(`${Math.floor(cents/100)}.${String(cents%100).padStart(2,'0')}`);const q=i%100+1;assert.equal(calculateInvoice([{quantity:q,unit_price:value}],0).total,BigInt(cents)*BigInt(q));}
 const v={...validFixture,items:[{description:'Test',quantity:3,unit_price:0.1}],tax:0,total:0.3};assert.equal(checkInvoice(v).passed,true);assert.equal(checkInvoice({...v,total:0.31}).passed,false);
});
test('PDF and JPG accepted, mismatched extensions and suspicious names rejected',()=>{
 for(const n of ['invoice.pdf','invoice.JPG','invoice.jpeg','invoice.docx','invoice.xlsx','invoice.txt'])assert.doesNotThrow(()=>validateDocument(n,documentMime(n),100));
 assert.throws(()=>validateDocument('invoice.jpg','application/pdf',100));assert.throws(()=>validateDocument('../invoice.txt','text/plain',100));assert.throws(()=>validateDocument('invoice.exe','application/octet-stream',100));
});
test('file byte validation rejects disguised executable and Office active content',async()=>{
 await assert.rejects(()=>inspectDocument(strToU8('not a pdf'),'invoice.pdf','application/pdf'));
 await assert.rejects(()=>inspectDocument(strToU8('MZ fake JPEG'),'invoice.jpg','image/jpeg'));
 const macro=zipSync({'word/document.xml':strToU8('<w:p/>'),'word/vbaProject.bin':strToU8('bad')});await assert.rejects(()=>officeText(macro,'invoice.docx'),/macros/);
 const external=zipSync({'word/document.xml':strToU8('<w:p/>'),'word/_rels/document.xml.rels':strToU8('<Relationship TargetMode="External"/>')});await assert.rejects(()=>officeText(external,'invoice.docx'),/external/);
});
test('real PDF text extraction preserves a wrong printed total and blocks active scripts',async()=>{
 const lines=['Supplier: PDF Supplies','Invoice number: PDF-001','Invoice date: 2026-10-01','Due date: 2026-11-01','Currency: INR','Paper  |  10  |  50','Tax: INR 0','Grand total: INR 700'];
 const result=await inspectDocument(testPdf(lines),'invoice.pdf','application/pdf');const data=parseInvoiceText(result.text);assert.equal(data.supplier,'PDF Supplies');assert.equal(data.items[0].quantity,10);assert.equal(data.total,700);assert.equal(checkInvoice({...validFixture,...data} as never).passed,false);
 await assert.rejects(()=>inspectDocument(testPdf(lines,true),'active.pdf','application/pdf'),/scripts/);
});
test('real JPG bytes decode successfully with bounded pixel dimensions',async()=>{
 const bytes=await sharp({create:{width:600,height:800,channels:3,background:'white'}}).jpeg().toBuffer();assert.equal((await inspectDocument(bytes,'invoice.jpg','image/jpeg')).visual,true);
 const tiny=await sharp({create:{width:10,height:10,channels:3,background:'white'}}).jpeg().toBuffer();await assert.rejects(()=>inspectDocument(tiny,'invoice.jpg','image/jpeg'),/readable/);
});
test('confidential company isolation, MFA, audited access and server-owned uploads',async()=>{
 const pg=new PGlite();await pg.waitReady;try{
 await pg.exec(`create role anon;create role authenticated;create schema auth;create schema storage;create schema extensions;
 create table auth.users(id uuid primary key,aud text,role text,email text,raw_user_meta_data jsonb);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('aal',coalesce(nullif(current_setting('request.jwt.claim.aal',true),''),'aal1'))$$;
 grant usage on schema auth,storage to authenticated;grant execute on function auth.uid(),auth.jwt() to authenticated;
 create function extensions.digest(v text,kind text) returns bytea language sql immutable as $$select sha256(convert_to(v,'UTF8'))$$;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
 alter table storage.objects enable row level security;grant select,insert,delete on storage.objects to authenticated;
 create function storage.foldername(v text) returns text[] language sql immutable as $$select string_to_array(v,'/')$$;`);
 for(const f of ['database/001_invoiceflow.sql','database/002_documents_and_gemini.sql','supabase/migrations/20261030143512_enterprise_controls.sql','supabase/migrations/20261030152200_manager_document_review.sql'])await pg.exec(readFileSync(f,'utf8'));
 await pg.exec(`insert into auth.users(id,email,raw_user_meta_data) values('10000000-0000-0000-0000-000000000001','manager-a@example.invalid','{}'),('10000000-0000-0000-0000-000000000002','employee-a@example.invalid','{}');insert into public.profiles(id,name,role) select id,email,case when email like 'manager%' then 'manager' else 'employee' end from auth.users;insert into private.settings(key,value) values('review_hash',encode(extensions.digest('server-test','sha256'),'hex')),('gemini_configuration','{"encrypted_key":"old-encrypted-value","model":"test"}');`);
 await pg.exec(readFileSync('supabase/migrations/20261030200016_confidential_workspaces_and_pdf_jpg.sql','utf8'));
 await pg.exec(readFileSync('supabase/migrations/20261030203146_private_security_rpc_implementations.sql','utf8'));
 const sql=readFileSync('tests/security-database.sql','utf8');await pg.exec(sql);
 const r=await pg.query<{name:string;passed:boolean}>('select * from security_results');for(const row of r.rows)assert.equal(row.passed,true,row.name);assert.ok(r.rows.length>=30);console.log(`Security: ${r.rows.length} company/MFA/upload assertions passed`);
 }finally{await pg.close();}
});
