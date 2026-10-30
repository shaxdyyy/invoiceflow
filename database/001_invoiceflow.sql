-- InvoiceFlow initial schema. Run on a dedicated Supabase project.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
create table private.settings (key text primary key, value text not null);
alter table private.settings enable row level security;
create table public.profiles (
 id uuid primary key references auth.users(id), name text not null,
 role text not null default 'employee' check(role in ('employee','manager')),
 created_at timestamptz not null default now()
);
create table public.invoices (
 id uuid primary key default gen_random_uuid(), client_id uuid not null,
 created_by uuid not null references public.profiles(id),
 supplier text not null, invoice_number text not null, invoice_date date not null, due_date date not null,
 category text not null, items jsonb not null, tax numeric(16,2) not null, total numeric(16,2) not null, notes text not null default '',
 status text not null default 'submitted' check(status in ('submitted','processing','needs_correction','pending_approval','approved','rejected','escalated')),
 attempts integer not null default 0, checks jsonb, review_summary text, review_mode text check(review_mode in ('rules','ai')),
 model_tokens integer not null default 0, decision_note text, decided_by uuid references public.profiles(id),
 run_id uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(created_by, client_id)
);
create unique index invoice_supplier_number on public.invoices(lower(btrim(supplier)),lower(btrim(invoice_number)));
create index invoice_owner on public.invoices(created_by);
create index invoice_status on public.invoices(status);
create index invoice_decider on public.invoices(decided_by);
create table public.activity (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id),
 actor_id uuid not null references public.profiles(id), event text not null, details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index activity_invoice on public.activity(invoice_id,created_at);
create index activity_actor on public.activity(actor_id,created_at);
alter table public.profiles enable row level security;
alter table public.invoices enable row level security;
alter table public.activity enable row level security;
revoke all on public.profiles,public.invoices,public.activity from anon,authenticated;
grant select on public.profiles,public.invoices,public.activity to authenticated;

create function private.is_manager() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='manager');
$$;
revoke all on function private.is_manager() from public,anon;
grant execute on function private.is_manager() to authenticated;
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()) or (select private.is_manager()));
create policy invoice_read on public.invoices for select to authenticated using(created_by=(select auth.uid()) or (select private.is_manager()));
create policy activity_read on public.activity for select to authenticated using(exists(select 1 from public.invoices i where i.id=invoice_id and (i.created_by=(select auth.uid()) or (select private.is_manager()))));

create function private.ensure_profile() returns public.profiles language plpgsql security definer set search_path='' as $$
declare result public.profiles;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 insert into public.profiles(id,name) select id,coalesce(nullif(left(raw_user_meta_data->>'name',80),''),split_part(email,'@',1),'Team member') from auth.users where id=auth.uid() on conflict(id) do nothing;
 select * into result from public.profiles where id=auth.uid(); return result;
end $$;

create function private.claim_manager(p_code text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 perform private.ensure_profile();
 perform pg_advisory_xact_lock(90018273);
 if exists(select 1 from public.profiles where role='manager') then raise exception 'Workspace already has a manager. Ask them to grant access.'; end if;
 if not exists(select 1 from private.settings where key='setup_hash' and value=encode(extensions.digest(p_code,'sha256'),'hex')) then raise exception 'Invalid setup code'; end if;
 update public.profiles set role='manager' where id=auth.uid();
 delete from private.settings where key='setup_hash';
end $$;

create function private.validate_input(p jsonb) returns void language plpgsql security invoker set search_path='' as $$
declare item jsonb; v numeric;
begin
 if jsonb_typeof(p)<>'object' or length(p::text)>12000 then raise exception 'Invalid invoice payload'; end if;
 if length(btrim(coalesce(p->>'supplier','')))<2 or length(p->>'supplier')>160 or length(btrim(coalesce(p->>'invoice_number','')))<1 or length(p->>'invoice_number')>80 then raise exception 'Supplier and invoice number are required'; end if;
 if coalesce(p->>'category','') not in ('Office supplies','Software & services','Equipment','Travel','Other') then raise exception 'Select a valid category'; end if;
 if coalesce(p->>'invoice_date','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(p->>'due_date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Valid dates are required'; end if;
 perform (p->>'invoice_date')::date; perform (p->>'due_date')::date;
 if jsonb_typeof(p->'items') is distinct from 'array' then raise exception 'Line items are required'; end if;
 if jsonb_array_length(p->'items') not between 1 and 30 then raise exception 'Use between 1 and 30 line items'; end if;
 for item in select * from jsonb_array_elements(p->'items') loop
  if length(btrim(coalesce(item->>'description','')))<1 or length(item->>'description')>200 then raise exception 'Every item needs a description'; end if;
  if jsonb_typeof(item->'quantity') is distinct from 'number' or jsonb_typeof(item->'unit_price') is distinct from 'number' then raise exception 'Invalid item amounts'; end if;
  v:=(item->>'quantity')::numeric; if v<1 or v>100000 or v<>trunc(v) then raise exception 'Quantity must be a positive integer'; end if;
  v:=(item->>'unit_price')::numeric; if v<0 or v>100000000 or v<>round(v,2) then raise exception 'Invalid unit price'; end if;
 end loop;
 if jsonb_typeof(p->'tax') is distinct from 'number' or jsonb_typeof(p->'total') is distinct from 'number' then raise exception 'Tax and total are required'; end if;
 v:=(p->>'tax')::numeric; if v<0 or v>100000000 or v<>round(v,2) then raise exception 'Invalid tax'; end if;
 v:=(p->>'total')::numeric; if v<=0 or v>100000000 or v<>round(v,2) then raise exception 'Invalid total'; end if;
 if length(coalesce(p->>'notes',''))>1500 then raise exception 'Notes are too long'; end if;
end $$;

create function private.create_invoice(p_input jsonb,p_client_id uuid) returns public.invoices language plpgsql security definer set search_path='' as $$
declare result public.invoices;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 perform private.ensure_profile();
 select * into result from public.invoices where created_by=auth.uid() and client_id=p_client_id;
 if found then return result; end if;
 perform private.validate_input(p_input);
 insert into public.invoices(client_id,created_by,supplier,invoice_number,invoice_date,due_date,category,items,tax,total,notes)
 values(p_client_id,auth.uid(),btrim(p_input->>'supplier'),btrim(p_input->>'invoice_number'),(p_input->>'invoice_date')::date,(p_input->>'due_date')::date,p_input->>'category',p_input->'items',(p_input->>'tax')::numeric,(p_input->>'total')::numeric,coalesce(p_input->>'notes','')) returning * into result;
 insert into public.activity(invoice_id,actor_id,event,details) values(result.id,auth.uid(),'invoice_submitted',jsonb_build_object('input',p_input));
 return result;
exception when unique_violation then
 select * into result from public.invoices where created_by=auth.uid() and client_id=p_client_id;
 if found then return result; end if;
 raise exception 'An invoice with this supplier and invoice number already exists';
end $$;

create function private.amend_invoice(p_id uuid,p_input jsonb) returns void language plpgsql security definer set search_path='' as $$
declare old public.invoices;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into old from public.invoices where id=p_id and created_by=auth.uid() for update;
 if not found or old.status<>'needs_correction' then raise exception 'Only your invoices needing correction can be edited'; end if;
 perform private.validate_input(p_input);
 update public.invoices set supplier=btrim(p_input->>'supplier'),invoice_number=btrim(p_input->>'invoice_number'),invoice_date=(p_input->>'invoice_date')::date,due_date=(p_input->>'due_date')::date,category=p_input->>'category',items=p_input->'items',tax=(p_input->>'tax')::numeric,total=(p_input->>'total')::numeric,notes=coalesce(p_input->>'notes',''),status='submitted',attempts=0,checks=null,review_summary=null,review_mode=null,run_id=null,updated_at=now() where id=p_id;
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'invoice_corrected',jsonb_build_object('before',to_jsonb(old),'after',p_input));
end $$;

create function private.start_review(p_id uuid) returns public.invoices language plpgsql security definer set search_path='' as $$
declare result public.invoices;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into result from public.invoices where id=p_id and (created_by=auth.uid() or private.is_manager()) for update;
 if not found then raise exception 'Invoice not found'; end if;
 if result.status in ('pending_approval','approved','rejected','needs_correction') then return result; end if;
 if result.status='processing' and result.updated_at>now()-interval '2 minutes' then raise exception 'Review already in progress'; end if;
 if result.attempts>=2 then raise exception 'Review attempt limit reached. Escalate to a person.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if (select count(*) from public.activity where actor_id=auth.uid() and event='review_started' and created_at>now()-interval '1 day')>=10 then raise exception 'Daily review limit reached (10). No paid fallback is enabled.'; end if;
 update public.invoices set status='processing',attempts=attempts+1,run_id=gen_random_uuid(),updated_at=now() where id=p_id returning * into result;
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'review_started',jsonb_build_object('attempt',result.attempts,'run_id',result.run_id));
 return result;
end $$;

create function private.finish_review(p_id uuid,p_run_id uuid,p_secret text,p_result jsonb) returns public.invoices language plpgsql security definer set search_path='' as $$
declare result public.invoices; expected numeric; valid boolean; v_checks jsonb; next_status text;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if not exists(select 1 from private.settings where key='review_hash' and value=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'Server authorization failed'; end if;
 if length(p_result::text)>30000 then raise exception 'Review result too large'; end if;
 select * into result from public.invoices where id=p_id and (created_by=auth.uid() or private.is_manager()) for update;
 if not found or result.status<>'processing' or result.run_id is distinct from p_run_id then raise exception 'Stale or invalid review run'; end if;
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric)+result.tax into expected from jsonb_array_elements(result.items) x;
 valid:=expected=result.total and result.due_date>=result.invoice_date and expected<=1000000;
 v_checks:=jsonb_build_object('passed',valid,'expected_total',expected,'checks',jsonb_build_array(
  jsonb_build_object('code','required','label','Required information','passed',true,'detail','Required fields validated by the database.'),
  jsonb_build_object('code','arithmetic','label','Line items & total','passed',expected=result.total,'detail','Expected INR '||expected||'; submitted INR '||result.total),
  jsonb_build_object('code','duplicate','label','Duplicate prevention','passed',true,'detail','Unique supplier and invoice number enforced by the database.'),
  jsonb_build_object('code','dates','label','Date order','passed',result.due_date>=result.invoice_date,'detail','Due date must be on or after invoice date.'),
  jsonb_build_object('code','amount_limit','label','Review amount limit','passed',expected<=1000000,'detail','Prototype review limit: INR 10,00,000.')));
 next_status:=case when not valid then 'needs_correction' when coalesce(p_result->>'error','')<>'' then 'escalated' else 'pending_approval' end;
 if p_result->>'mode' not in ('rules','ai') then raise exception 'Invalid review mode'; end if;
 update public.invoices set status=next_status,checks=v_checks,review_summary=left(coalesce(p_result->>'summary','No review summary supplied'),4000),review_mode=p_result->>'mode',model_tokens=model_tokens+greatest(0,least(100000,coalesce((p_result->>'tokens')::integer,0))),updated_at=now() where id=p_id returning * into result;
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'review_completed',jsonb_build_object('status',next_status,'mode',p_result->>'mode','checks',v_checks,'trace',p_result->'trace','error',p_result->>'error','run_id',p_run_id));
 return result;
end $$;

create function private.decide_invoice(p_id uuid,p_decision text,p_note text) returns public.invoices language plpgsql security definer set search_path='' as $$
declare result public.invoices; expected numeric;
begin
 if auth.uid() is null or not private.is_manager() then raise exception 'Manager permission required'; end if;
 if p_decision not in ('approved','rejected') or length(btrim(p_note))<5 or length(p_note)>1000 then raise exception 'Choose a decision and add a reason (5–1000 characters)'; end if;
 select * into result from public.invoices where id=p_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if result.created_by=auth.uid() then raise exception 'A different manager must decide your own submission'; end if;
 if result.status<>'pending_approval' or result.checks->>'passed'<>'true' then raise exception 'Invoice must pass review before a decision'; end if;
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric)+result.tax into expected from jsonb_array_elements(result.items) x;
 if expected<>result.total or result.due_date<result.invoice_date or expected>1000000 then raise exception 'Independent checks failed'; end if;
 update public.invoices set status=p_decision,decision_note=btrim(p_note),decided_by=auth.uid(),updated_at=now() where id=p_id returning * into result;
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'invoice_'||p_decision,jsonb_build_object('reason',p_note,'previous_status','pending_approval'));
 return result;
end $$;

create function private.promote_member(p_member uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_manager() then raise exception 'Manager permission required'; end if;
 update public.profiles set role='manager' where id=p_member;
 if not found then raise exception 'Member not found'; end if;
end $$;

revoke all on function private.ensure_profile() from public,anon;
grant execute on function private.ensure_profile() to authenticated;
create function public.ensure_profile() returns public.profiles language sql security invoker set search_path='' as $$ select private.ensure_profile(); $$;
revoke all on function public.ensure_profile() from public,anon;
grant execute on function public.ensure_profile() to authenticated;

revoke all on function private.claim_manager(text) from public,anon;
grant execute on function private.claim_manager(text) to authenticated;
create function public.claim_manager(p_code text) returns void language sql security invoker set search_path='' as $$ select private.claim_manager(p_code); $$;
revoke all on function public.claim_manager(text) from public,anon;
grant execute on function public.claim_manager(text) to authenticated;

revoke all on function private.create_invoice(jsonb,uuid) from public,anon;
grant execute on function private.create_invoice(jsonb,uuid) to authenticated;
create function public.create_invoice(p_input jsonb,p_client_id uuid) returns public.invoices language sql security invoker set search_path='' as $$ select private.create_invoice(p_input,p_client_id); $$;
revoke all on function public.create_invoice(jsonb,uuid) from public,anon;
grant execute on function public.create_invoice(jsonb,uuid) to authenticated;

revoke all on function private.amend_invoice(uuid,jsonb) from public,anon;
grant execute on function private.amend_invoice(uuid,jsonb) to authenticated;
create function public.amend_invoice(p_id uuid,p_input jsonb) returns void language sql security invoker set search_path='' as $$ select private.amend_invoice(p_id,p_input); $$;
revoke all on function public.amend_invoice(uuid,jsonb) from public,anon;
grant execute on function public.amend_invoice(uuid,jsonb) to authenticated;

revoke all on function private.start_review(uuid) from public,anon;
grant execute on function private.start_review(uuid) to authenticated;
create function public.start_review(p_id uuid) returns public.invoices language sql security invoker set search_path='' as $$ select private.start_review(p_id); $$;
revoke all on function public.start_review(uuid) from public,anon;
grant execute on function public.start_review(uuid) to authenticated;

revoke all on function private.finish_review(uuid,uuid,text,jsonb) from public,anon;
grant execute on function private.finish_review(uuid,uuid,text,jsonb) to authenticated;
create function public.finish_review(p_id uuid,p_run_id uuid,p_secret text,p_result jsonb) returns public.invoices language sql security invoker set search_path='' as $$ select private.finish_review(p_id,p_run_id,p_secret,p_result); $$;
revoke all on function public.finish_review(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.finish_review(uuid,uuid,text,jsonb) to authenticated;

revoke all on function private.decide_invoice(uuid,text,text) from public,anon;
grant execute on function private.decide_invoice(uuid,text,text) to authenticated;
create function public.decide_invoice(p_id uuid,p_decision text,p_note text) returns public.invoices language sql security invoker set search_path='' as $$ select private.decide_invoice(p_id,p_decision,p_note); $$;
revoke all on function public.decide_invoice(uuid,text,text) from public,anon;
grant execute on function public.decide_invoice(uuid,text,text) to authenticated;

revoke all on function private.promote_member(uuid) from public,anon;
grant execute on function private.promote_member(uuid) to authenticated;
create function public.promote_member(p_member uuid) returns void language sql security invoker set search_path='' as $$ select private.promote_member(p_member); $$;
revoke all on function public.promote_member(uuid) from public,anon;
grant execute on function public.promote_member(uuid) to authenticated;

revoke all on function private.validate_input(jsonb) from public,anon,authenticated;
