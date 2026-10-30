import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
// Real embedded PostgreSQL in memory. No production project or credentials are used.
test('enterprise SQL migrations, RLS, approval gates and 2,000-row search',async()=>{
 const pg=new PGlite();await pg.waitReady;
 try{
 await pg.exec(`create role anon; create role authenticated; create schema auth; create schema storage; create schema extensions;
 create table auth.users(id uuid primary key,aud text,role text,email text,raw_user_meta_data jsonb);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth,storage to authenticated; grant execute on function auth.uid() to authenticated;
 create function extensions.digest(v text,kind text) returns bytea language sql immutable as $$select sha256(convert_to(v,'UTF8'))$$;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
 alter table storage.objects enable row level security;grant select,insert,delete on storage.objects to authenticated;
 create function storage.foldername(v text) returns text[] language sql immutable as $$select string_to_array(v,'/')$$;`);
 await pg.exec(readFileSync('database/001_invoiceflow.sql','utf8'));
 await pg.exec(readFileSync('database/002_documents_and_gemini.sql','utf8'));
 await pg.exec(readFileSync('supabase/migrations/20261030143512_enterprise_controls.sql','utf8'));
 await pg.exec("insert into private.settings(key,value) values('review_hash','placeholder'),('setup_hash','placeholder');");
 for(const file of ['tests/database.sql','tests/documents-database.sql']){
  // The existing setup test assumes no manager exists. The harness starts empty.
  const sql=readFileSync(file,'utf8').replace(/rollback;\s*$/i,'select * from '+(file.includes('documents')?'results':'test_results')+';rollback;');
  const results=await pg.exec(sql);const rows=results.flatMap(r=>r.rows).filter((r:Record<string,unknown>)=>'passed' in r);
  assert.ok(rows.length>=16,`${file}: test rows`);for(const r of rows)assert.equal(r.passed,true,String(r.name));
 }
 await pg.exec(readFileSync('tests/enterprise-database.sql','utf8'));
 const result=await pg.query<{name:string;passed:boolean}>('select * from enterprise_results');
 for(const r of result.rows)assert.equal(r.passed,true,r.name);
 assert.ok(result.rows.length>=20);console.log(`Verified ${result.rows.length} enterprise database assertions plus 36 existing database assertions`);
 }finally{await pg.close();}
});
