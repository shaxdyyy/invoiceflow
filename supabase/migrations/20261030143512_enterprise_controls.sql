-- Enterprise controls. Existing invoice and document records are preserved.

create table public.exception_cases(
 invoice_id uuid primary key references public.invoices(id), status text not null check(status in ('open','resolved')),
 assessment jsonb not null, plan text not null, engine text not null, updated_at timestamptz not null default now()
);
alter table public.exception_cases enable row level security;
revoke all on public.exception_cases from public,anon,authenticated;
grant select on public.exception_cases to authenticated;
create policy exception_case_read on public.exception_cases for select to authenticated using(exists(select 1 from public.invoices i where i.id=invoice_id and (i.created_by=(select auth.uid()) or (select private.is_manager()))));
create table private.assistant_usage(id uuid primary key default gen_random_uuid(),actor_id uuid not null,created_at timestamptz not null default now());
alter table private.assistant_usage enable row level security;
revoke all on private.assistant_usage from public,anon,authenticated;
create index assistant_usage_actor on private.assistant_usage(actor_id,created_at);
create index invoice_supplier_amount on public.invoices(lower(regexp_replace(supplier,'[^a-zA-Z0-9]','','g')),total,invoice_date);

create index invoice_search on public.invoices using gin(to_tsvector('simple',supplier||' '||invoice_number||' '||category));

create function private.assess_invoice(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.invoices; signals jsonb:='[]'; score integer:=0; blocked boolean:=false; n integer; historical integer; baseline numeric; expected numeric; line record; ordered numeric; received numeric; price numeric; used numeric; ok boolean; norm text;
begin
 if auth.uid() is null then raise exception 'Sign in first';end if;
 select * into r from public.invoices where id=p_id and (created_by=auth.uid() or private.is_manager());if not found then raise exception 'Invoice not accessible';end if;
 norm:=lower(regexp_replace(r.supplier,'[^a-zA-Z0-9]','','g'));
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric)+r.tax into expected from jsonb_array_elements(r.items) x;
 if expected<>r.total then signals:=signals||jsonb_build_array(jsonb_build_object('code','arithmetic','points',60,'blocking',true,'detail','Line items and tax do not equal the printed total.','next_action','Ask the supplier for a corrected invoice. Preserve the original total.'));end if;
 if r.due_date<r.invoice_date then signals:=signals||jsonb_build_array(jsonb_build_object('code','date_order','points',40,'blocking',true,'detail','Due date precedes invoice date.','next_action','Confirm the dates against the original.'));end if;
 if expected>1000000 then signals:=signals||jsonb_build_array(jsonb_build_object('code','amount_limit','points',60,'blocking',true,'detail','Invoice exceeds the prototype review limit.','next_action','Request a separate finance review.'));end if;
 select count(*) into n from public.invoices i where i.id<>r.id and i.status<>'rejected' and lower(regexp_replace(i.supplier,'[^a-zA-Z0-9]','','g'))=norm and lower(regexp_replace(i.invoice_number,'[^a-zA-Z0-9]','','g'))=lower(regexp_replace(r.invoice_number,'[^a-zA-Z0-9]','','g'));
 if n>0 then signals:=signals||jsonb_build_array(jsonb_build_object('code','duplicate_number','points',95,'blocking',true,'detail','Another non-rejected invoice has the same normalized supplier and invoice number.','next_action','Investigate the existing submission. Reject the duplicate after review.'));else
 select count(*) into n from public.invoices i where i.id<>r.id and i.status<>'rejected' and lower(regexp_replace(i.supplier,'[^a-zA-Z0-9]','','g'))=norm and i.total=r.total and i.invoice_date=r.invoice_date and (select jsonb_agg(jsonb_build_array(lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) order by lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) from jsonb_array_elements(i.items) x)=(select jsonb_agg(jsonb_build_array(lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) order by lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) from jsonb_array_elements(r.items) x);
 if n>0 then signals:=signals||jsonb_build_array(jsonb_build_object('code','duplicate_content','points',80,'blocking',true,'detail','Supplier, date, amount and line items match another non-rejected submission with a different number. Possible duplicate, not proof of fraud.','next_action','Check both originals and reject the duplicate, or correct the wrongly entered record.'));end if;end if;
 select count(*),percentile_cont(0.5) within group(order by total) into historical,baseline from public.invoices where id<>r.id and status='approved' and lower(regexp_replace(supplier,'[^a-zA-Z0-9]','','g'))=norm;
 if historical>=5 and baseline>0 and r.total>baseline*3 then signals:=signals||jsonb_build_array(jsonb_build_object('code','amount_outlier','points',35,'blocking',false,'detail','Amount exceeds three times the median of at least five approved supplier invoices.','next_action','Confirm the unusual purchase and supporting order.'));end if;
 if r.invoice_date>current_date+1 then signals:=signals||jsonb_build_array(jsonb_build_object('code','future_date','points',20,'blocking',false,'detail','Invoice date is in the future.','next_action','Confirm the issue date with the supplier.'));end if;
 select least(100,coalesce(sum((x->>'points')::int),0)),coalesce(bool_or((x->>'blocking')::boolean),false) into score,blocked from jsonb_array_elements(signals) x;
 return jsonb_build_object('score',score,'level',case when score>=60 then 'High' when score>=25 then 'Medium' else 'Low' end,'blocked',blocked,'signals',signals,'history_count',historical,'assessed_at',now());
end $$;

create function private.record_exception(p_id uuid,p_secret text,p_plan text,p_engine text) returns jsonb language plpgsql security definer set search_path='' as $$
declare assessment jsonb; plan text; state text;
begin
 if auth.uid() is null or not exists(select 1 from private.settings where key='review_hash' and value=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'Server authorization required';end if;
 assessment:=private.assess_invoice(p_id);state:=case when (assessment->>'blocked')::boolean or (assessment->>'score')::integer>=25 then 'open' else 'resolved' end;
 select string_agg(x->>'next_action',E'\n') into plan from jsonb_array_elements(assessment->'signals') x;
 if p_engine='ai' and length(p_plan) between 10 and 2500 then plan:=p_plan;end if;
 plan:=coalesce(plan,'No blocking exception found. Review the supporting business context before a manager decision.');
 insert into public.exception_cases(invoice_id,status,assessment,plan,engine) values(p_id,state,assessment,plan,case when p_engine='ai' then 'ai' else 'rules' end) on conflict(invoice_id) do update set status=excluded.status,assessment=excluded.assessment,plan=excluded.plan,engine=excluded.engine,updated_at=now();
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'exception_triaged',jsonb_build_object('status',state,'assessment',assessment,'plan',plan,'engine',p_engine));
 return assessment;
end $$;
create function private.reserve_assistant() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,29));
 if (select count(*) from private.assistant_usage where actor_id=auth.uid() and created_at>now()-interval '24 hours')>=20 then raise exception 'Daily assistant limit reached (20). Invoice search and rules checks remain available.';end if;
 insert into private.assistant_usage(actor_id) values(auth.uid());
end $$;
-- Approval enforcement is independent of browser and LLM output. Serialize approval decisions and recheck risk evidence.
create function private.enforce_enterprise_approval() returns trigger language plpgsql security definer set search_path='' as $$
declare assessment jsonb;
begin
 if new.status='approved' and old.status is distinct from new.status then
 perform pg_advisory_xact_lock(947320);assessment:=private.assess_invoice(old.id);
 if (assessment->>'blocked')::boolean then raise exception 'Approval blocked: resolve duplicate or calculation exceptions first';end if;
 end if;return new;
end $$;
create trigger enforce_enterprise_approval before update of status on public.invoices for each row execute function private.enforce_enterprise_approval();

-- Scoped, indexed, paginated search; never loads every invoice into a model prompt.
create function public.search_invoices(p_query text default '',p_status text default '',p_min numeric default 0,p_max numeric default 100000000,p_offset integer default 0,p_date_from date default null,p_date_to date default null) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('total',(select count(*) from public.invoices i where (p_date_from is null or i.invoice_date>=p_date_from) and (p_date_to is null or i.invoice_date<=p_date_to) and (p_status='' or i.status=p_status) and i.total between p_min and p_max and (btrim(p_query)='' or to_tsvector('simple',i.supplier||' '||i.invoice_number||' '||i.category) @@ websearch_to_tsquery('simple',left(p_query,160)) or i.invoice_number ilike '%'||left(p_query,80)||'%')),'invoices',coalesce((select jsonb_agg(to_jsonb(r)) from (select id,supplier,invoice_number,invoice_date,due_date,status,total,category from public.invoices i where (p_date_from is null or i.invoice_date>=p_date_from) and (p_date_to is null or i.invoice_date<=p_date_to) and (p_status='' or i.status=p_status) and i.total between p_min and p_max and (btrim(p_query)='' or to_tsvector('simple',i.supplier||' '||i.invoice_number||' '||i.category) @@ websearch_to_tsquery('simple',left(p_query,160)) or i.invoice_number ilike '%'||left(p_query,80)||'%') order by created_at desc,id limit 20 offset greatest(0,least(p_offset,100000))) r),'[]'::jsonb));
$$;

revoke all on function private.assess_invoice(uuid) from public,anon;
grant execute on function private.assess_invoice(uuid) to authenticated;
create function public.assess_invoice(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.assess_invoice(p_id); $$;
revoke all on function public.assess_invoice(uuid) from public,anon;
grant execute on function public.assess_invoice(uuid) to authenticated;

revoke all on function private.record_exception(uuid,text,text,text) from public,anon;
grant execute on function private.record_exception(uuid,text,text,text) to authenticated;
create function public.record_exception(p_id uuid,p_secret text,p_plan text,p_engine text) returns jsonb language sql security invoker set search_path='' as $$ select private.record_exception(p_id,p_secret,p_plan,p_engine); $$;
revoke all on function public.record_exception(uuid,text,text,text) from public,anon;
grant execute on function public.record_exception(uuid,text,text,text) to authenticated;

revoke all on function private.reserve_assistant() from public,anon;
grant execute on function private.reserve_assistant() to authenticated;
create function public.reserve_assistant() returns void language sql security invoker set search_path='' as $$ select private.reserve_assistant(); $$;
revoke all on function public.reserve_assistant() from public,anon;
grant execute on function public.reserve_assistant() to authenticated;

revoke all on function public.search_invoices(text,text,numeric,numeric,integer,date,date) from public,anon;
grant execute on function public.search_invoices(text,text,numeric,numeric,integer,date,date) to authenticated;
revoke all on function private.enforce_enterprise_approval() from public,anon,authenticated;
create or replace function private.register_document(p_path text,p_name text,p_mime text,p_size integer) returns public.documents language plpgsql security definer set search_path='' as $$
declare result public.documents;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 perform private.ensure_profile();
 if split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='invoice-documents' and name=p_path) then raise exception 'Upload your document first'; end if;
 if length(p_name)>180 or p_mime not in ('application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain') then raise exception 'Unsupported document'; end if;
 if not ((p_mime='text/plain' and lower(p_name) like '%.txt') or (p_mime='application/vnd.openxmlformats-officedocument.wordprocessingml.document' and lower(p_name) like '%.docx') or (p_mime='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' and lower(p_name) like '%.xlsx')) then raise exception 'Use DOCX, XLSX or TXT';end if;
 insert into public.documents(owner_id,storage_path,filename,mime_type,file_size) values(auth.uid(),p_path,p_name,p_mime,p_size) returning * into result;return result;
end $$;
update storage.buckets set allowed_mime_types=array['application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain'] where id='invoice-documents';
