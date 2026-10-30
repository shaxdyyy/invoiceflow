-- Enterprise controls. Existing invoice and document records are preserved.
alter table public.invoices add column purchase_order_number text not null default '', add column matching_mode text not null default 'none' check(matching_mode in ('none','two_way','three_way'));
create table public.purchase_orders(
 id uuid primary key default gen_random_uuid(), reference text not null unique check(length(reference) between 1 and 80),
 supplier text not null check(length(supplier) between 2 and 160), items jsonb not null,
 receipt_reference text not null default '', created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now()
);
alter table public.purchase_orders enable row level security;
revoke all on public.purchase_orders from public,anon,authenticated;
grant select on public.purchase_orders to authenticated;
create policy purchase_order_read on public.purchase_orders for select to authenticated using ((select private.is_manager()));
create index purchase_orders_creator on public.purchase_orders(created_by);
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
create index invoice_po on public.invoices(purchase_order_number) where purchase_order_number<>'';
create index invoice_search on public.invoices using gin(to_tsvector('simple',supplier||' '||invoice_number||' '||category));

create function private.save_purchase_order(p_data jsonb) returns public.purchase_orders language plpgsql security definer set search_path='' as $$
declare r public.purchase_orders; line jsonb; d text; seen text[]:=array[]::text[];
begin
 if auth.uid() is null or not private.is_manager() then raise exception 'Manager permission required'; end if;
 perform pg_advisory_xact_lock(947320);
 if length(p_data::text)>14000 or length(btrim(coalesce(p_data->>'reference',''))) not between 1 and 80 or length(btrim(coalesce(p_data->>'supplier',''))) not between 2 and 160 or jsonb_typeof(p_data->'items')<>'array' or jsonb_array_length(p_data->'items') not between 1 and 30 then raise exception 'Enter a reference, supplier and 1–30 line items';end if;
 for line in select * from jsonb_array_elements(p_data->'items') loop
  d:=lower(btrim(coalesce(line->>'description','')));
  if length(d) not between 1 and 200 or d=any(seen) or (line->>'quantity') is null or (line->>'quantity')::numeric not between 1 and 100000 or (line->>'quantity')::numeric<>trunc((line->>'quantity')::numeric) or (line->>'unit_price') is null or (line->>'unit_price')::numeric not between 0 and 100000000 or round((line->>'unit_price')::numeric,2)<>(line->>'unit_price')::numeric or (line->>'received') is null or (line->>'received')::numeric not between 0 and (line->>'quantity')::numeric or (line->>'received')::numeric<>trunc((line->>'received')::numeric) then raise exception 'Use unique item names, whole quantities and prices with at most 2 decimals';end if;
  seen:=array_append(seen,d);
 end loop;
 if exists(select 1 from jsonb_array_elements(p_data->'items') x where (x->>'received')::numeric>0) and length(btrim(coalesce(p_data->>'receipt_reference',''))) not between 1 and 120 then raise exception 'Add a goods receipt reference for received quantities';end if;
 insert into public.purchase_orders(reference,supplier,items,receipt_reference,created_by) values(upper(btrim(p_data->>'reference')),btrim(p_data->>'supplier'),p_data->'items',left(btrim(coalesce(p_data->>'receipt_reference','')),120),auth.uid()) on conflict(reference) do update set supplier=excluded.supplier,items=excluded.items,receipt_reference=excluded.receipt_reference,updated_at=now() returning * into r;
 perform private.refresh_order_cases(r.reference);
 return r;
end $$;
create function private.set_invoice_matching(p_id uuid,p_mode text,p_reference text) returns void language plpgsql security definer set search_path='' as $$
declare r public.invoices;
begin
 if auth.uid() is null then raise exception 'Sign in first';end if;
 perform pg_advisory_xact_lock(947320);
 select * into r from public.invoices where id=p_id and (created_by=auth.uid() or private.is_manager()) for update;
 if not found or r.status in ('approved','rejected','processing') then raise exception 'Invoice cannot be changed';end if;
 if ((r.matching_mode<>'none' and p_mode='none') or (r.matching_mode='three_way' and p_mode='two_way')) and not private.is_manager() then raise exception 'Only a manager can reduce configured matching';end if;
 if p_mode not in ('none','two_way','three_way') or length(p_reference)>80 or (p_mode<>'none' and btrim(p_reference)='') then raise exception 'Choose matching mode and purchase order reference';end if;
 update public.invoices set matching_mode=p_mode,purchase_order_number=case when p_mode='none' then '' else upper(btrim(p_reference)) end,updated_at=now() where id=p_id;
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'matching_configured',jsonb_build_object('mode',p_mode,'reference',p_reference));
end $$;

create function private.assess_invoice(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.invoices; po public.purchase_orders; signals jsonb:='[]'; matches jsonb:='[]'; score integer:=0; blocked boolean:=false; n integer; historical integer; baseline numeric; expected numeric; line record; ordered numeric; received numeric; price numeric; used numeric; ok boolean; norm text;
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
 if r.matching_mode='none' then
 matches:=jsonb_build_array(jsonb_build_object('label','Supporting documents','passed',false,'detail','Matching not configured. Select a purchase order to enable two-way or three-way matching.'));
 else
 select * into po from public.purchase_orders where reference=r.purchase_order_number;
 if not found then matches:=matches||jsonb_build_array(jsonb_build_object('label','Purchase order exists','passed',false,'detail','No saved purchase order matches this reference.'));else
 matches:=matches||jsonb_build_array(jsonb_build_object('label','Supplier matches purchase order','passed',lower(regexp_replace(po.supplier,'[^a-zA-Z0-9]','','g'))=norm,'detail','Invoice supplier must match the saved order.'));
 for line in select lower(btrim(x->>'description')) description,sum((x->>'quantity')::numeric) quantity,min((x->>'unit_price')::numeric) min_price,max((x->>'unit_price')::numeric) max_price from jsonb_array_elements(r.items) x group by lower(btrim(x->>'description')) loop
  select (x->>'quantity')::numeric,(x->>'received')::numeric,(x->>'unit_price')::numeric into ordered,received,price from jsonb_array_elements(po.items) x where lower(btrim(x->>'description'))=line.description;
  select coalesce(sum((x->>'quantity')::numeric),0) into used from public.invoices i cross join lateral jsonb_array_elements(i.items) x where i.id<>r.id and i.status='approved' and i.purchase_order_number=r.purchase_order_number and lower(btrim(x->>'description'))=line.description;
  ok:=ordered is not null and line.min_price=price and line.max_price=price and line.quantity+used<=ordered;
  matches:=matches||jsonb_build_array(jsonb_build_object('label',line.description||' · order quantity and price','passed',coalesce(ok,false),'detail','Current quantity '||line.quantity||'; previously approved '||used||'; ordered '||coalesce(ordered::text,'not found')||'. Unit price must match exactly.'));
  if r.matching_mode='three_way' then matches:=matches||jsonb_build_array(jsonb_build_object('label',line.description||' · goods received','passed',coalesce(received is not null and line.quantity+used<=received and po.receipt_reference<>'',false),'detail','Recorded received quantity '||coalesce(received::text,'0')||'; receipt '||coalesce(nullif(po.receipt_reference,''),'missing')||'.'));end if;
 end loop;end if;
 if exists(select 1 from jsonb_array_elements(matches) x where (x->>'passed')::boolean=false) then signals:=signals||jsonb_build_array(jsonb_build_object('code','matching_exception','points',60,'blocking',true,'detail','Purchase order or receipt matching failed.','next_action','Ask the manager to verify the order, quantities, prices and goods receipt; then run checks again.'));end if;
 end if;
 select least(100,coalesce(sum((x->>'points')::int),0)),coalesce(bool_or((x->>'blocking')::boolean),false) into score,blocked from jsonb_array_elements(signals) x;
 return jsonb_build_object('score',score,'level',case when score>=60 then 'High' when score>=25 then 'Medium' else 'Low' end,'blocked',blocked,'signals',signals,'matching',matches,'matching_mode',r.matching_mode,'history_count',historical,'assessed_at',now());
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
create function private.refresh_order_cases(p_reference text) returns void language plpgsql security definer set search_path='' as $$
declare r record; a jsonb; plan text; state text;
begin
 if auth.uid() is null or not private.is_manager() then raise exception 'Manager permission required';end if;
 for r in select id from public.invoices where purchase_order_number=p_reference and status not in ('approved','rejected') loop
  a:=private.assess_invoice(r.id);state:=case when (a->>'blocked')::boolean or (a->>'score')::int>=25 then 'open' else 'resolved' end;
  select string_agg(x->>'next_action',E'\n') into plan from jsonb_array_elements(a->'signals') x;
  plan:=coalesce(plan,'Order and receipt rechecked. No blocking exception found. A different manager must make the invoice decision.');
  insert into public.exception_cases(invoice_id,status,assessment,plan,engine) values(r.id,state,a,plan,'rules') on conflict(invoice_id) do update set status=excluded.status,assessment=excluded.assessment,plan=excluded.plan,engine='rules',updated_at=now();
  insert into public.activity(invoice_id,actor_id,event,details) values(r.id,auth.uid(),'order_evidence_rechecked',jsonb_build_object('reference',p_reference,'assessment',a,'status',state));
 end loop;
end $$;
revoke all on function private.refresh_order_cases(text) from public,anon,authenticated;
create function private.reserve_assistant() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,29));
 if (select count(*) from private.assistant_usage where actor_id=auth.uid() and created_at>now()-interval '24 hours')>=20 then raise exception 'Daily assistant limit reached (20). Invoice search and rules checks remain available.';end if;
 insert into private.assistant_usage(actor_id) values(auth.uid());
end $$;
-- Approval enforcement is independent of browser and LLM output. Serialize decisions to prevent double billing a PO.
create function private.enforce_enterprise_approval() returns trigger language plpgsql security definer set search_path='' as $$
declare assessment jsonb;
begin
 if new.status='approved' and old.status is distinct from new.status then
 perform pg_advisory_xact_lock(947320);assessment:=private.assess_invoice(old.id);
 if (assessment->>'blocked')::boolean then raise exception 'Approval blocked: resolve duplicate or matching exceptions first';end if;
 end if;return new;
end $$;
create trigger enforce_enterprise_approval before update of status on public.invoices for each row execute function private.enforce_enterprise_approval();

-- Scoped, indexed, paginated search; never loads every invoice into a model prompt.
create function public.search_invoices(p_query text default '',p_status text default '',p_min numeric default 0,p_max numeric default 100000000,p_offset integer default 0,p_date_from date default null,p_date_to date default null) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('total',(select count(*) from public.invoices i where (p_date_from is null or i.invoice_date>=p_date_from) and (p_date_to is null or i.invoice_date<=p_date_to) and (p_status='' or i.status=p_status) and i.total between p_min and p_max and (btrim(p_query)='' or to_tsvector('simple',i.supplier||' '||i.invoice_number||' '||i.category) @@ websearch_to_tsquery('simple',left(p_query,160)) or i.invoice_number ilike '%'||left(p_query,80)||'%')),'invoices',coalesce((select jsonb_agg(to_jsonb(r)) from (select id,supplier,invoice_number,invoice_date,due_date,status,total,category from public.invoices i where (p_date_from is null or i.invoice_date>=p_date_from) and (p_date_to is null or i.invoice_date<=p_date_to) and (p_status='' or i.status=p_status) and i.total between p_min and p_max and (btrim(p_query)='' or to_tsvector('simple',i.supplier||' '||i.invoice_number||' '||i.category) @@ websearch_to_tsquery('simple',left(p_query,160)) or i.invoice_number ilike '%'||left(p_query,80)||'%') order by created_at desc,id limit 20 offset greatest(0,least(p_offset,100000))) r),'[]'::jsonb));
$$;

revoke all on function private.save_purchase_order(jsonb) from public,anon;
grant execute on function private.save_purchase_order(jsonb) to authenticated;
create function public.save_purchase_order(p_data jsonb) returns public.purchase_orders language sql security invoker set search_path='' as $$ select private.save_purchase_order(p_data); $$;
revoke all on function public.save_purchase_order(jsonb) from public,anon;
grant execute on function public.save_purchase_order(jsonb) to authenticated;

revoke all on function private.set_invoice_matching(uuid,text,text) from public,anon;
grant execute on function private.set_invoice_matching(uuid,text,text) to authenticated;
create function public.set_invoice_matching(p_id uuid,p_mode text,p_reference text) returns void language sql security invoker set search_path='' as $$ select private.set_invoice_matching(p_id,p_mode,p_reference); $$;
revoke all on function public.set_invoice_matching(uuid,text,text) from public,anon;
grant execute on function public.set_invoice_matching(uuid,text,text) to authenticated;

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
