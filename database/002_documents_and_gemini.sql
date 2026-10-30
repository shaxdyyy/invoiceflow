-- Private source documents and encrypted Gemini integration.
create table private.extraction_usage(id uuid primary key default gen_random_uuid(),actor_id uuid not null,created_at timestamptz not null default now());
alter table private.extraction_usage enable row level security;
create index extraction_usage_actor on private.extraction_usage(actor_id,created_at);
revoke all on private.extraction_usage from public,anon,authenticated;
create table public.documents (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),
 filename text not null,mime_type text not null,storage_path text not null unique,file_size integer not null check(file_size between 1 and 3145728),
 invoice_id uuid references public.invoices(id),status text not null default 'uploaded' check(status in ('uploaded','extracting','needs_input','extracted','failed','linked')),
 extraction_attempts integer not null default 0,run_id uuid,extracted jsonb,engine text,error text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.documents enable row level security;
create index documents_owner on public.documents(owner_id,created_at);
create index documents_invoice on public.documents(invoice_id);
revoke all on public.documents from anon,authenticated;
grant select on public.documents to authenticated;
create policy document_read on public.documents for select to authenticated using(owner_id=(select auth.uid()) or (select private.is_manager()));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('invoice-documents','invoice-documents',false,3145728,array['application/pdf','image/png','image/jpeg','image/webp','text/plain']) on conflict(id) do nothing;
create policy invoice_document_insert on storage.objects for insert to authenticated with check(bucket_id='invoice-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy invoice_document_select on storage.objects for select to authenticated using(bucket_id='invoice-documents' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select private.is_manager())));
create policy invoice_document_cleanup on storage.objects for delete to authenticated using(bucket_id='invoice-documents' and (storage.foldername(name))[1]=(select auth.uid())::text and not exists(select 1 from public.documents where storage_path=name));

create function private.register_document(p_path text,p_name text,p_mime text,p_size integer) returns public.documents language plpgsql security definer set search_path='' as $$
declare result public.documents;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 perform private.ensure_profile();
 if split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='invoice-documents' and name=p_path) then raise exception 'Upload your document first'; end if;
 if length(p_name)>180 or p_mime not in ('application/pdf','image/png','image/jpeg','image/webp','text/plain') then raise exception 'Unsupported document'; end if;
 insert into public.documents(owner_id,storage_path,filename,mime_type,file_size) values(auth.uid(),p_path,p_name,p_mime,p_size) returning * into result;return result;
end $$;
create function private.start_extraction(p_id uuid) returns public.documents language plpgsql security definer set search_path='' as $$
declare result public.documents;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into result from public.documents where id=p_id and owner_id=auth.uid() for update;
 if not found then raise exception 'Document not found'; end if;
 if result.status in ('linked','extracted','needs_input') then return result; end if;
 if result.status='extracting' and result.updated_at>now()-interval '2 minutes' then raise exception 'Document is already being read'; end if;
 if result.extraction_attempts>=2 then raise exception 'Two extraction attempts used. Enter the details manually or ask for help.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,17));
 if (select count(*) from private.extraction_usage where actor_id=auth.uid() and created_at>now()-interval '24 hours')>=10 then raise exception 'Daily document analysis limit reached. Use local reading or manual entry.'; end if;
 insert into private.extraction_usage(actor_id) values(auth.uid());
 update public.documents set status='extracting',extraction_attempts=extraction_attempts+1,run_id=gen_random_uuid(),updated_at=now() where id=p_id returning * into result;return result;
end $$;
create function private.finish_extraction(p_id uuid,p_run_id uuid,p_secret text,p_data jsonb,p_error text) returns public.documents language plpgsql security definer set search_path='' as $$
declare result public.documents;
begin
 if auth.uid() is null or not exists(select 1 from private.settings where key='review_hash' and value=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'Server authorization required'; end if;
 select * into result from public.documents where id=p_id and owner_id=auth.uid() for update;
 if not found or result.status<>'extracting' or result.run_id is distinct from p_run_id then raise exception 'Stale extraction'; end if;
 if length(p_data::text)>40000 then raise exception 'Extraction too large'; end if;
 update public.documents set status=case when p_error<>'' then 'failed' when jsonb_array_length(coalesce(p_data->'uncertainties','[]'::jsonb))>0 then 'needs_input' else 'extracted' end,extracted=p_data,error=nullif(left(p_error,1000),''),engine='gemini',updated_at=now() where id=p_id returning * into result;return result;
end $$;
create function private.link_document(p_id uuid,p_invoice uuid,p_engine text) returns void language plpgsql security definer set search_path='' as $$
declare doc public.documents;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into doc from public.documents where id=p_id and owner_id=auth.uid() for update;
 if not found then raise exception 'Document is not yours'; end if;
 if doc.invoice_id=p_invoice then return; end if;
 if doc.invoice_id is not null then raise exception 'Document is already linked'; end if;
 if p_engine='gemini' and (doc.engine is distinct from 'gemini' or doc.status not in ('extracted','needs_input')) then raise exception 'Gemini extraction is not complete'; end if;
 if not exists(select 1 from public.invoices where id=p_invoice and created_by=auth.uid()) then raise exception 'Invoice not found'; end if;
 if p_engine not in ('gemini','local-text','local-ocr','manual') then raise exception 'Invalid extraction engine'; end if;
 update public.documents set invoice_id=p_invoice,status='linked',engine=p_engine,updated_at=now() where id=p_id;
 insert into public.activity(invoice_id,actor_id,event,details) values(p_invoice,auth.uid(),'source_document_attached',jsonb_build_object('document_id',p_id,'filename',doc.filename,'engine',p_engine,'extraction_attempts',doc.extraction_attempts));
end $$;
create function private.provider_configuration(p_secret text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from private.settings where key='review_hash' and value=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'Server authorization required'; end if;
 return coalesce((select value::jsonb from private.settings where key='gemini_configuration'),'{}'::jsonb);
end $$;
create function private.save_provider_configuration(p_secret text,p_configuration jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_manager() then raise exception 'Manager access required'; end if;
 if not exists(select 1 from private.settings where key='review_hash' and value=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'Server authorization required'; end if;
 if p_configuration is null then delete from private.settings where key='gemini_configuration';return;end if;
 if length(p_configuration::text)>3000 then raise exception 'Invalid provider configuration'; end if;
 insert into private.settings(key,value) values('gemini_configuration',p_configuration::text) on conflict(key) do update set value=excluded.value;
end $$;

revoke all on function private.register_document(text,text,text,integer) from public,anon;
grant execute on function private.register_document(text,text,text,integer) to authenticated;
create function public.register_document(p_path text,p_name text,p_mime text,p_size integer) returns public.documents language sql security invoker set search_path='' as $$ select private.register_document(p_path,p_name,p_mime,p_size); $$;
revoke all on function public.register_document(text,text,text,integer) from public,anon;
grant execute on function public.register_document(text,text,text,integer) to authenticated;

revoke all on function private.start_extraction(uuid) from public,anon;
grant execute on function private.start_extraction(uuid) to authenticated;
create function public.start_extraction(p_id uuid) returns public.documents language sql security invoker set search_path='' as $$ select private.start_extraction(p_id); $$;
revoke all on function public.start_extraction(uuid) from public,anon;
grant execute on function public.start_extraction(uuid) to authenticated;

revoke all on function private.finish_extraction(uuid,uuid,text,jsonb,text) from public,anon;
grant execute on function private.finish_extraction(uuid,uuid,text,jsonb,text) to authenticated;
create function public.finish_extraction(p_id uuid,p_run_id uuid,p_secret text,p_data jsonb,p_error text) returns public.documents language sql security invoker set search_path='' as $$ select private.finish_extraction(p_id,p_run_id,p_secret,p_data,p_error); $$;
revoke all on function public.finish_extraction(uuid,uuid,text,jsonb,text) from public,anon;
grant execute on function public.finish_extraction(uuid,uuid,text,jsonb,text) to authenticated;

revoke all on function private.link_document(uuid,uuid,text) from public,anon;
grant execute on function private.link_document(uuid,uuid,text) to authenticated;
create function public.link_document(p_id uuid,p_invoice uuid,p_engine text) returns void language sql security invoker set search_path='' as $$ select private.link_document(p_id,p_invoice,p_engine); $$;
revoke all on function public.link_document(uuid,uuid,text) from public,anon;
grant execute on function public.link_document(uuid,uuid,text) to authenticated;

revoke all on function private.provider_configuration(text) from public,anon;
grant execute on function private.provider_configuration(text) to authenticated;
create function public.provider_configuration(p_secret text) returns jsonb language sql security invoker set search_path='' as $$ select private.provider_configuration(p_secret); $$;
revoke all on function public.provider_configuration(text) from public,anon;
grant execute on function public.provider_configuration(text) to authenticated;

revoke all on function private.save_provider_configuration(text,jsonb) from public,anon;
grant execute on function private.save_provider_configuration(text,jsonb) to authenticated;
create function public.save_provider_configuration(p_secret text,p_configuration jsonb) returns void language sql security invoker set search_path='' as $$ select private.save_provider_configuration(p_secret,p_configuration); $$;
revoke all on function public.save_provider_configuration(text,jsonb) from public,anon;
grant execute on function public.save_provider_configuration(text,jsonb) to authenticated;
