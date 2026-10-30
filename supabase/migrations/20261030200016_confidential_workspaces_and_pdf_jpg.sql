-- Company boundaries and manager MFA. Existing data stays together in its original company.
create table public.workspaces(id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 2 and 100),cloud_ai_allowed boolean not null default false,created_at timestamptz not null default now());
alter table public.workspaces enable row level security;
revoke all on public.workspaces from public,anon,authenticated;grant select on public.workspaces to authenticated;
alter table public.profiles add column workspace_id uuid references public.workspaces(id);
alter table public.invoices add column workspace_id uuid references public.workspaces(id);
alter table public.documents add column workspace_id uuid references public.workspaces(id);
do $$declare w uuid;begin
 insert into public.workspaces(name) values('InvoiceFlow company') returning id into w;
 update public.profiles set workspace_id=w;update public.invoices set workspace_id=w;update public.documents set workspace_id=w;
end $$;
alter table public.invoices alter column workspace_id set not null;
alter table public.documents alter column workspace_id set not null;
create index profiles_workspace on public.profiles(workspace_id);
create index invoices_workspace on public.invoices(workspace_id,created_at);
create index documents_workspace on public.documents(workspace_id,created_at);
drop index public.invoice_supplier_number;
create unique index invoice_supplier_number on public.invoices(workspace_id,lower(btrim(supplier)),lower(btrim(invoice_number)));

create function private.current_workspace() returns uuid language sql stable security definer set search_path='' as $$select workspace_id from public.profiles where id=auth.uid()$$;
create or replace function private.is_manager() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=auth.uid() and role='manager' and workspace_id is not null) and coalesce(auth.jwt()->>'aal','aal1')='aal2'$$;
create function private.can_read_owner(p_owner uuid) returns boolean language sql stable security definer set search_path='' as $$select private.current_workspace() is not null and exists(select 1 from public.profiles where id=p_owner and workspace_id=private.current_workspace()) and (p_owner=auth.uid() or private.is_manager())$$;
create function private.require_resource(p_id uuid,p_kind text) returns void language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or private.current_workspace() is null then raise exception 'Join or create a company workspace first';end if;
 if p_kind='document' and exists(select 1 from public.documents where id=p_id and private.can_read_owner(owner_id)) then return;end if;
 if p_kind='invoice' and exists(select 1 from public.invoices where id=p_id and private.can_read_owner(created_by)) then return;end if;
 raise exception 'Record not accessible in this company';end $$;
revoke all on function private.current_workspace(),private.can_read_owner(uuid),private.require_resource(uuid,text) from public,anon;
grant execute on function private.current_workspace(),private.can_read_owner(uuid) to authenticated;

drop policy profile_read on public.profiles;
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()) or (workspace_id=(select private.current_workspace()) and (select private.is_manager())));
drop policy invoice_read on public.invoices;
create policy invoice_read on public.invoices for select to authenticated using(workspace_id=(select private.current_workspace()) and private.can_read_owner(created_by));
drop policy document_read on public.documents;
create policy document_read on public.documents for select to authenticated using(workspace_id=(select private.current_workspace()) and private.can_read_owner(owner_id));
create policy workspace_read on public.workspaces for select to authenticated using(id=(select private.current_workspace()));
-- Related rows inherit their accessible parent's boundary through its RLS.
drop policy invoice_document_select on storage.objects;
create policy invoice_document_select on storage.objects for select to authenticated using(bucket_id='invoice-documents' and private.current_workspace() is not null and (((storage.foldername(name))[1]=(select auth.uid())::text) or exists(select 1 from public.documents d where d.storage_path=name and d.workspace_id=private.current_workspace() and private.is_manager())));
drop policy invoice_document_insert on storage.objects;
create policy invoice_document_insert on storage.objects for insert to authenticated with check(bucket_id='invoice-documents' and private.current_workspace() is not null and (storage.foldername(name))[1]=(select auth.uid())::text);
-- Storage objects have no UPDATE policy. Registered originals cannot be replaced or deleted.
update storage.buckets set public=false,file_size_limit=3145728,allowed_mime_types=array['application/pdf','image/jpeg','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain'] where id='invoice-documents';

create function private.assign_company() returns trigger language plpgsql security definer set search_path='' as $$declare w uuid;begin
 select workspace_id into w from public.profiles where id=case when tg_table_name='documents' then (to_jsonb(new)->>'owner_id')::uuid else (to_jsonb(new)->>'created_by')::uuid end;
 if w is null then raise exception 'Company membership required';end if;
 if tg_op='UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'Company cannot be changed';end if;
 if new.workspace_id is not null and new.workspace_id<>w then raise exception 'Company mismatch';end if;
 new.workspace_id:=w;return new;end $$;
revoke all on function private.assign_company() from public,anon,authenticated;
create trigger document_company before insert or update on public.documents for each row execute function private.assign_company();
create trigger invoice_company before insert or update on public.invoices for each row execute function private.assign_company();

create table private.company_invitations(id uuid primary key default gen_random_uuid(),workspace_id uuid not null references public.workspaces(id),code_hash text unique not null,created_by uuid not null references public.profiles(id),expires_at timestamptz not null,used_at timestamptz);
create table public.security_events(id uuid primary key default gen_random_uuid(),workspace_id uuid not null references public.workspaces(id),actor_id uuid not null references public.profiles(id),event text not null,details jsonb not null default '{}',created_at timestamptz not null default now());
alter table private.company_invitations enable row level security;revoke all on private.company_invitations from public,anon,authenticated;
alter table public.security_events enable row level security;revoke all on public.security_events from public,anon,authenticated;grant select on public.security_events to authenticated;
create index security_events_workspace on public.security_events(workspace_id,created_at);
create index security_events_actor on public.security_events(actor_id);
create index company_invitations_workspace on private.company_invitations(workspace_id);
create index company_invitations_creator on private.company_invitations(created_by);
create policy security_events_read on public.security_events for select to authenticated using(workspace_id=(select private.current_workspace()) and (select private.is_manager()));

create function public.workspace_context() returns jsonb language sql stable security invoker set search_path='' as $$select jsonb_build_object('workspace_id',p.workspace_id,'name',w.name,'cloud_ai_allowed',coalesce(w.cloud_ai_allowed,false),'role',p.role,'mfa_verified',coalesce(auth.jwt()->>'aal','aal1')='aal2') from public.profiles p left join public.workspaces w on w.id=p.workspace_id where p.id=auth.uid()$$;
create function public.create_company(p_name text) returns uuid language plpgsql security definer set search_path='' as $$declare w uuid;begin
 perform private.ensure_profile();perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,81));
 if private.current_workspace() is not null then raise exception 'You already belong to a company';end if;
 if length(btrim(p_name)) not between 2 and 100 then raise exception 'Use a company name of 2 to 100 characters';end if;
 insert into public.workspaces(name) values(btrim(p_name)) returning id into w;
 update public.profiles set workspace_id=w,role='manager' where id=auth.uid();
 insert into public.security_events(workspace_id,actor_id,event) values(w,auth.uid(),'company_created');return w;end $$;
create function public.create_company_invitation() returns text language plpgsql security definer set search_path='' as $$declare code text;begin
 if not private.is_manager() then raise exception 'Manager two-factor authentication required';end if;
 if (select count(*) from private.company_invitations where workspace_id=private.current_workspace() and expires_at>now() and used_at is null)>=20 then raise exception 'Use or revoke existing invitations first';end if;
 code:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into private.company_invitations(workspace_id,code_hash,created_by,expires_at) values(private.current_workspace(),encode(extensions.digest(code,'sha256'),'hex'),auth.uid(),now()+interval '24 hours');
 insert into public.security_events(workspace_id,actor_id,event) values(private.current_workspace(),auth.uid(),'invitation_created');return code;end $$;
create function public.join_company(p_code text) returns void language plpgsql security definer set search_path='' as $$declare inv private.company_invitations;begin
 perform private.ensure_profile();perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,81));
 if private.current_workspace() is not null then raise exception 'You already belong to a company';end if;
 select * into inv from private.company_invitations where code_hash=encode(extensions.digest(p_code,'sha256'),'hex') and used_at is null and expires_at>now() for update;
 if not found then raise exception 'Invitation is invalid, expired or already used';end if;
 update public.profiles set workspace_id=inv.workspace_id,role='employee' where id=auth.uid();
 update private.company_invitations set used_at=now() where id=inv.id;
 insert into public.security_events(workspace_id,actor_id,event) values(inv.workspace_id,auth.uid(),'invitation_accepted');end $$;
create function public.configure_company(p_cloud_ai boolean,p_name text) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.is_manager() then raise exception 'Manager two-factor authentication required';end if;
 if length(btrim(p_name)) not between 2 and 100 then raise exception 'Use a company name of 2 to 100 characters';end if;
 update public.workspaces set cloud_ai_allowed=p_cloud_ai,name=btrim(p_name) where id=private.current_workspace();
 insert into public.security_events(workspace_id,actor_id,event,details) values(private.current_workspace(),auth.uid(),'company_security_updated',jsonb_build_object('cloud_ai_allowed',p_cloud_ai));end $$;
create function public.revoke_company_invitations() returns void language plpgsql security definer set search_path='' as $$begin
 if not private.is_manager() then raise exception 'Manager two-factor authentication required';end if;
 update private.company_invitations set expires_at=now() where workspace_id=private.current_workspace() and used_at is null;
 insert into public.security_events(workspace_id,actor_id,event) values(private.current_workspace(),auth.uid(),'invitations_revoked');end $$;
create function public.record_document_access(p_id uuid) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_resource(p_id,'document');
 insert into public.security_events(workspace_id,actor_id,event,details) values(private.current_workspace(),auth.uid(),'original_opened',jsonb_build_object('document_id',p_id));end $$;
create function public.reserve_upload() returns void language plpgsql security definer set search_path='' as $$begin
 if private.current_workspace() is null then raise exception 'Company membership required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,82));
 if (select count(*) from public.security_events where actor_id=auth.uid() and event='upload_started' and created_at>now()-interval '1 hour')>=30 then raise exception 'Upload limit reached. Try again in an hour.';end if;
 insert into public.security_events(workspace_id,actor_id,event) values(private.current_workspace(),auth.uid(),'upload_started');end $$;

-- Scope encrypted provider credentials and consent to one company. Never return plaintext keys.
create table private.company_provider(workspace_id uuid primary key references public.workspaces(id),configuration jsonb not null);
alter table private.company_provider enable row level security;revoke all on private.company_provider from public,anon,authenticated;
insert into private.company_provider(workspace_id,configuration) select w.id,s.value::jsonb from public.workspaces w cross join private.settings s where s.key='gemini_configuration';
delete from private.settings where key='gemini_configuration';
create or replace function private.provider_configuration(p_secret text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.authorize_document_server(p_secret);
 if private.current_workspace() is null then raise exception 'Company membership required';end if;
 return coalesce((select configuration from private.company_provider where workspace_id=private.current_workspace()),'{}'::jsonb)||jsonb_build_object('cloud_ai_allowed',(select cloud_ai_allowed from public.workspaces where id=private.current_workspace()));end $$;
create or replace function private.save_provider_configuration(p_secret text,p_configuration jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.authorize_document_server(p_secret);
 if not private.is_manager() then raise exception 'Manager two-factor authentication required';end if;
 if p_configuration is null then delete from private.company_provider where workspace_id=private.current_workspace();return;end if;
 if length(p_configuration::text)>3000 then raise exception 'Invalid configuration';end if;
 insert into private.company_provider(workspace_id,configuration) values(private.current_workspace(),p_configuration) on conflict(workspace_id) do update set configuration=excluded.configuration;
 insert into public.security_events(workspace_id,actor_id,event) values(private.current_workspace(),auth.uid(),'provider_connected');end $$;

-- Server validates actual file bytes before this registration API can run.
create function public.register_validated_document(p_path text,p_name text,p_mime text,p_size integer,p_secret text) returns public.documents language plpgsql security definer set search_path='' as $$declare d public.documents;begin
 perform private.authorize_document_server(p_secret);if private.current_workspace() is null then raise exception 'Company membership required';end if;
 if split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='invoice-documents' and name=p_path) then raise exception 'Original not uploaded';end if;
 if length(p_name) not between 1 and 180 or p_name~'[[:cntrl:]/\\]' or p_size not between 1 and 3145728 then raise exception 'Invalid document';end if;
 if not ((p_mime='application/pdf' and lower(p_name) like '%.pdf') or (p_mime='image/jpeg' and lower(p_name) ~ '\.(jpg|jpeg)$') or (p_mime='text/plain' and lower(p_name) like '%.txt') or (p_mime='application/vnd.openxmlformats-officedocument.wordprocessingml.document' and lower(p_name) like '%.docx') or (p_mime='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' and lower(p_name) like '%.xlsx')) then raise exception 'Use PDF, JPG, DOCX, XLSX or TXT';end if;
 insert into public.documents(owner_id,storage_path,filename,mime_type,file_size) values(auth.uid(),p_path,p_name,p_mime,p_size) returning * into d;
 insert into public.security_events(workspace_id,actor_id,event,details) values(private.current_workspace(),auth.uid(),'document_uploaded',jsonb_build_object('document_id',d.id,'type',p_mime));return d;end $$;
revoke execute on function public.register_document(text,text,text,integer),private.register_document(text,text,text,integer),public.start_extraction(uuid),private.start_extraction(uuid),public.claim_manager(text),private.claim_manager(text) from authenticated;
revoke all on function public.workspace_context(),public.create_company(text),public.create_company_invitation(),public.join_company(text),public.configure_company(boolean,text),public.revoke_company_invitations(),public.record_document_access(uuid),public.reserve_upload(),public.register_validated_document(text,text,text,integer,text) from public,anon;
grant execute on function public.workspace_context(),public.create_company(text),public.create_company_invitation(),public.join_company(text),public.configure_company(boolean,text),public.revoke_company_invitations(),public.record_document_access(uuid),public.reserve_upload(),public.register_validated_document(text,text,text,integer,text) to authenticated;

create or replace function private.promote_member(p_member uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.is_manager() then raise exception 'Manager two-factor authentication required';end if;
 update public.profiles set role='manager' where id=p_member and workspace_id=private.current_workspace();if not found then raise exception 'Member not accessible';end if;
 insert into public.security_events(workspace_id,actor_id,event,details) values(private.current_workspace(),auth.uid(),'member_promoted',jsonb_build_object('member_id',p_member));end $$;

-- Explicit tenant checks inside privileged functions, including nested calls.


create or replace function private.start_document_read(p_id uuid,p_secret text,p_ai boolean) returns public.documents language plpgsql security definer set search_path='' as $$
declare d public.documents;
begin
 perform private.require_resource(p_id,'document');
 perform private.authorize_document_server(p_secret);
 select * into d from public.documents where id=p_id and (owner_id=auth.uid() or private.is_manager()) for update;
 if not found then raise exception 'Document not accessible';end if;
 if d.extracted is not null or d.review_state='rejected' then return d;end if;
 if p_ai then
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,17));
 if (select count(*) from private.extraction_usage where actor_id=auth.uid() and created_at>now()-interval '24 hours')>=10 then raise exception 'Daily AI extraction limit reached. Retry when quota resets.';end if;
 end if;
 if d.status='extracting' and d.updated_at>now()-interval '2 minutes' then raise exception 'Document already being read';end if;
 if d.extraction_attempts>=2 then raise exception 'Two reading attempts used. Ask a manager to investigate the document.';end if;
 if p_ai then insert into private.extraction_usage(actor_id) values(auth.uid());end if;
 update public.documents set status='extracting',run_id=gen_random_uuid(),extraction_attempts=extraction_attempts+1,updated_at=now() where id=p_id returning * into d;return d;
end $$;

create or replace function private.finish_document_read(p_id uuid,p_run_id uuid,p_secret text,p_data jsonb,p_text text,p_hash text,p_engine text,p_error text default '') returns public.documents language plpgsql security definer set search_path='' as $$
declare d public.documents;
begin
 perform private.require_resource(p_id,'document');
 perform private.authorize_document_server(p_secret);
 select * into d from public.documents where id=p_id and (owner_id=auth.uid() or private.is_manager()) for update;
 if not found or d.status<>'extracting' or d.run_id is distinct from p_run_id or d.extracted is not null then raise exception 'Stale document read';end if;
 if p_error<>'' then update public.documents set status='failed',error=left(p_error,1000),updated_at=now() where id=p_id returning * into d;return d;end if;
 if length(p_text)>24000 or length(p_data::text)>40000 or p_hash!~'^[a-f0-9]{64}$' or p_engine not in ('gemini','local-text') or jsonb_typeof(p_data->'uncertainties') is distinct from 'array' then raise exception 'Invalid extraction snapshot';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_hash,34));
 update public.documents set extracted=p_data,source_text=p_text,content_hash=p_hash,engine=p_engine,review_state=case when jsonb_array_length(p_data->'uncertainties')>0 then 'needs_input' else 'ready' end,status=case when jsonb_array_length(p_data->'uncertainties')>0 then 'needs_input' else 'extracted' end,error=null,updated_at=now() where id=p_id returning * into d;
 return d;
end $$;

create or replace function private.commit_document(p_id uuid,p_secret text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.documents;r public.invoices;a jsonb;
begin
 perform private.require_resource(p_id,'document');
 perform private.authorize_document_server(p_secret);
 select * into d from public.documents where id=p_id and (owner_id=auth.uid() or private.is_manager()) for update;
 if not found or d.extracted is null then raise exception 'Document extraction required';end if;
 if d.invoice_id is not null then return jsonb_build_object('invoice_id',d.invoice_id);end if;
 if jsonb_array_length(coalesce(d.extracted->'uncertainties','[]'))>0 then return jsonb_build_object('needs_input',true);end if;
 begin
 r:=private.write_document_invoice(p_id,d.extracted);
 exception when others then update public.documents set review_state='needs_input',error=left(sqlerrm,1000) where id=p_id;return jsonb_build_object('needs_input',true,'error',sqlerrm);end;
 a:=private.record_exception(r.id,p_secret,'','rules');
 return jsonb_build_object('invoice_id',r.id,'assessment',a);
end $$;

create or replace function private.write_document_invoice(p_id uuid,p_input jsonb) returns public.invoices language plpgsql security definer set search_path='' as $$
declare d public.documents;r public.invoices;expected numeric;valid boolean;v_checks jsonb;
begin
 perform private.require_resource(p_id,'document');
 select * into d from public.documents where id=p_id for update;
 if d.extracted is null or d.review_state in ('approved','rejected') then raise exception 'Document is not available for review';end if;
 perform private.validate_input(p_input);
 if coalesce(p_input->>'currency','')<>'INR' then raise exception 'Only INR invoices may be reviewed';end if;
 if d.content_hash is not null then
 perform pg_advisory_xact_lock(hashtextextended(d.content_hash,34));
 if exists(select 1 from public.documents x left join public.invoices i on i.id=x.invoice_id where x.workspace_id=d.workspace_id and x.id<>d.id and x.content_hash=d.content_hash and x.review_state<>'rejected' and coalesce(i.status,'')<>'rejected' and (x.invoice_id is not null or x.created_at<d.created_at or (x.created_at=d.created_at and x.id<d.id))) then raise exception 'Duplicate document: this original has already been uploaded. Review or reject the earlier copy.';end if;end if;
 if d.invoice_id is null then
 insert into public.invoices(client_id,created_by,supplier,invoice_number,invoice_date,due_date,category,items,tax,total,notes) values(d.id,d.owner_id,btrim(p_input->>'supplier'),btrim(p_input->>'invoice_number'),(p_input->>'invoice_date')::date,(p_input->>'due_date')::date,p_input->>'category',p_input->'items',(p_input->>'tax')::numeric,(p_input->>'total')::numeric,coalesce(p_input->>'notes','')) returning * into r;
 update public.documents set invoice_id=r.id,status='linked' where id=d.id;
 insert into public.activity(invoice_id,actor_id,event,details) values(r.id,auth.uid(),'document_invoice_created',jsonb_build_object('document_id',d.id,'engine',d.engine,'source_owner',d.owner_id));
 else
 select * into r from public.invoices where id=d.invoice_id for update;
 if r.status in ('approved','rejected','processing') then raise exception 'Finalized or active invoices cannot be changed';end if;
 update public.invoices set supplier=btrim(p_input->>'supplier'),invoice_number=btrim(p_input->>'invoice_number'),invoice_date=(p_input->>'invoice_date')::date,due_date=(p_input->>'due_date')::date,category=p_input->>'category',items=p_input->'items',tax=(p_input->>'tax')::numeric,total=(p_input->>'total')::numeric,notes=coalesce(p_input->>'notes','') where id=r.id returning * into r;
 end if;
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric)+r.tax into expected from jsonb_array_elements(r.items) x;
 valid:=expected=r.total and r.due_date>=r.invoice_date and expected<=1000000;
 v_checks:=jsonb_build_object('passed',valid,'expected_total',expected,'checks',jsonb_build_array(
 jsonb_build_object('code','required','label','Required information','passed',true,'detail','Required fields validated against the saved extraction.'),
 jsonb_build_object('code','arithmetic','label','Line items & total','passed',expected=r.total,'detail','Expected INR '||expected||'; invoice INR '||r.total),
 jsonb_build_object('code','dates','label','Date order','passed',r.due_date>=r.invoice_date,'detail','Due date must be on or after issue date.'),
 jsonb_build_object('code','amount_limit','label','Review limit','passed',expected<=1000000,'detail','Prototype review limit is INR 10,00,000.')));
 update public.invoices set status=case when valid then 'pending_approval' else 'needs_correction' end,checks=v_checks,review_mode='rules',review_summary=case when valid then 'Calculations passed. Compare the original and extracted details before deciding.' else 'Calculations or dates need attention. The original printed figures have been preserved.' end,updated_at=now() where id=r.id returning * into r;
 update public.documents set review_data=p_input,review_state=case when valid then 'ready' else 'needs_input' end,updated_at=now() where id=d.id;
 return r;
end $$;

create or replace function private.review_document(p_id uuid,p_revision integer,p_input jsonb,p_reason text,p_action text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.documents;r public.invoices;a jsonb;next_revision integer;before_data jsonb;
begin
 perform private.require_resource(p_id,'document');
 if auth.uid() is null or not private.is_manager() then raise exception 'Manager permission required';end if;
 if p_action not in ('save','approve','reject') or length(btrim(p_reason)) not between 5 and 1000 then raise exception 'Add a correction or decision reason (5–1000 characters)';end if;
 perform pg_advisory_xact_lock(947320);
 select * into d from public.documents where id=p_id for update;
 if not found or d.revision<>p_revision then raise exception 'This document changed. Reload before saving.';end if;
 if d.review_state in ('approved','rejected') then raise exception 'Finalized documents cannot be changed';end if;
 before_data:=coalesce(d.review_data,d.extracted);next_revision:=d.revision+1;
 if p_action='reject' then
 if d.invoice_id is not null then r:=private.decide_invoice(d.invoice_id,'rejected',p_reason);else update public.documents set review_state='rejected',revision=next_revision,updated_at=now() where id=p_id;end if;
 insert into public.document_audit(document_id,actor_id,action,reason,before_data,after_data,revision) values(p_id,auth.uid(),'rejected',p_reason,before_data,before_data,next_revision);
 return jsonb_build_object('document_id',p_id,'invoice_id',d.invoice_id,'state','rejected');end if;
 if d.extracted is null then raise exception 'Read the document before correction. Do not invent an extraction.';end if;
 r:=private.write_document_invoice(p_id,p_input);
 a:=private.assess_invoice(r.id);
 update public.documents set revision=next_revision,error=null where id=p_id;
 insert into public.document_audit(document_id,actor_id,action,reason,before_data,after_data,revision) values(p_id,auth.uid(),'manager_correction',p_reason,before_data,p_input,next_revision);
 insert into public.activity(invoice_id,actor_id,event,details) values(r.id,auth.uid(),'manager_extraction_corrected',jsonb_build_object('document_id',p_id,'before',before_data,'after',p_input,'reason',p_reason,'revision',next_revision));
 insert into public.exception_cases(invoice_id,status,assessment,plan,engine) values(r.id,case when (a->>'blocked')::boolean or (a->>'score')::int>=25 then 'open' else 'resolved' end,a,coalesce((select string_agg(x->>'next_action',E'\n') from jsonb_array_elements(a->'signals') x),'No blocking exception found. Compare the original before approval.'),'rules') on conflict(invoice_id) do update set status=excluded.status,assessment=excluded.assessment,plan=excluded.plan,engine='rules',updated_at=now();
 if p_action='approve' and not (a->>'blocked')::boolean and (r.checks->>'passed')::boolean then
 r:=private.decide_invoice(r.id,'approved',p_reason);
 insert into public.document_audit(document_id,actor_id,action,reason,before_data,after_data,revision) values(p_id,auth.uid(),'approved',p_reason,p_input,p_input,next_revision+1);
 end if;
 return jsonb_build_object('document_id',p_id,'invoice_id',r.id,'state',r.status,'assessment',a,'blocked',(a->>'blocked')::boolean);
end $$;

create or replace function private.start_review(p_id uuid) returns public.invoices language plpgsql security definer set search_path='' as $$
declare result public.invoices;
begin
 perform private.require_resource(p_id,'invoice');
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

create or replace function private.finish_review(p_id uuid,p_run_id uuid,p_secret text,p_result jsonb) returns public.invoices language plpgsql security definer set search_path='' as $$
declare result public.invoices; expected numeric; valid boolean; v_checks jsonb; next_status text;
begin
 perform private.require_resource(p_id,'invoice');
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

create or replace function private.assess_invoice(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.invoices; signals jsonb:='[]'; score integer:=0; blocked boolean:=false; n integer; historical integer; baseline numeric; expected numeric; line record; ordered numeric; received numeric; price numeric; used numeric; ok boolean; norm text;
begin
 perform private.require_resource(p_id,'invoice');
 if auth.uid() is null then raise exception 'Sign in first';end if;
 select * into r from public.invoices where id=p_id and (created_by=auth.uid() or private.is_manager());if not found then raise exception 'Invoice not accessible';end if;
 norm:=lower(regexp_replace(r.supplier,'[^a-zA-Z0-9]','','g'));
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric)+r.tax into expected from jsonb_array_elements(r.items) x;
 if expected<>r.total then signals:=signals||jsonb_build_array(jsonb_build_object('code','arithmetic','points',60,'blocking',true,'detail','Line items and tax do not equal the printed total.','next_action','Ask the supplier for a corrected invoice. Preserve the original total.'));end if;
 if r.due_date<r.invoice_date then signals:=signals||jsonb_build_array(jsonb_build_object('code','date_order','points',40,'blocking',true,'detail','Due date precedes invoice date.','next_action','Confirm the dates against the original.'));end if;
 if expected>1000000 then signals:=signals||jsonb_build_array(jsonb_build_object('code','amount_limit','points',60,'blocking',true,'detail','Invoice exceeds the prototype review limit.','next_action','Request a separate finance review.'));end if;
 select count(*) into n from public.invoices i where i.workspace_id=r.workspace_id and i.id<>r.id and i.status<>'rejected' and lower(regexp_replace(i.supplier,'[^a-zA-Z0-9]','','g'))=norm and lower(regexp_replace(i.invoice_number,'[^a-zA-Z0-9]','','g'))=lower(regexp_replace(r.invoice_number,'[^a-zA-Z0-9]','','g'));
 if n>0 then signals:=signals||jsonb_build_array(jsonb_build_object('code','duplicate_number','points',95,'blocking',true,'detail','Another non-rejected invoice has the same normalized supplier and invoice number.','next_action','Investigate the existing submission. Reject the duplicate after review.'));else
 select count(*) into n from public.invoices i where i.workspace_id=r.workspace_id and i.id<>r.id and i.status<>'rejected' and lower(regexp_replace(i.supplier,'[^a-zA-Z0-9]','','g'))=norm and i.total=r.total and i.invoice_date=r.invoice_date and (select jsonb_agg(jsonb_build_array(lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) order by lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) from jsonb_array_elements(i.items) x)=(select jsonb_agg(jsonb_build_array(lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) order by lower(btrim(x->>'description')),(x->>'quantity')::numeric,(x->>'unit_price')::numeric) from jsonb_array_elements(r.items) x);
 if n>0 then signals:=signals||jsonb_build_array(jsonb_build_object('code','duplicate_content','points',80,'blocking',true,'detail','Supplier, date, amount and line items match another non-rejected submission with a different number. Possible duplicate, not proof of fraud.','next_action','Check both originals and reject the duplicate, or correct the wrongly entered record.'));end if;end if;
 select count(*),percentile_cont(0.5) within group(order by total) into historical,baseline from public.invoices where workspace_id=r.workspace_id and id<>r.id and status='approved' and lower(regexp_replace(supplier,'[^a-zA-Z0-9]','','g'))=norm;
 if historical>=5 and baseline>0 and r.total>baseline*3 then signals:=signals||jsonb_build_array(jsonb_build_object('code','amount_outlier','points',35,'blocking',false,'detail','Amount exceeds three times the median of at least five approved supplier invoices.','next_action','Confirm the unusual purchase and supporting order.'));end if;
 if r.invoice_date>current_date+1 then signals:=signals||jsonb_build_array(jsonb_build_object('code','future_date','points',20,'blocking',false,'detail','Invoice date is in the future.','next_action','Confirm the issue date with the supplier.'));end if;
 select least(100,coalesce(sum((x->>'points')::int),0)),coalesce(bool_or((x->>'blocking')::boolean),false) into score,blocked from jsonb_array_elements(signals) x;
 return jsonb_build_object('score',score,'level',case when score>=60 then 'High' when score>=25 then 'Medium' else 'Low' end,'blocked',blocked,'signals',signals,'history_count',historical,'assessed_at',now());
end $$;

create or replace function private.decide_invoice(p_id uuid,p_decision text,p_note text) returns public.invoices language plpgsql security definer set search_path='' as $$
declare r public.invoices;a jsonb;
begin
 perform private.require_resource(p_id,'invoice');
 if auth.uid() is null or not private.is_manager() then raise exception 'Manager permission required';end if;
 if p_decision not in ('approved','rejected') or length(btrim(p_note)) not between 5 and 1000 then raise exception 'Add a decision reason (5–1000 characters)';end if;
 perform pg_advisory_xact_lock(947320);
 select * into r from public.invoices where id=p_id for update;
 if not found or r.status in ('approved','rejected','processing') then raise exception 'Invoice cannot be decided';end if;
 if p_decision='approved' then
 a:=private.assess_invoice(p_id);
 if r.status<>'pending_approval' or coalesce((r.checks->>'passed')::boolean,false)=false or (a->>'blocked')::boolean then raise exception 'Approval blocked. Resolve missing details, duplicate flags or calculation errors first.';end if;
 if exists(select 1 from public.documents where invoice_id=p_id and review_state not in ('ready','approved')) then raise exception 'Document needs manager review';end if;
 end if;
 update public.invoices set status=p_decision,decided_by=auth.uid(),decision_note=btrim(p_note),updated_at=now() where id=p_id returning * into r;
 update public.documents set review_state=p_decision,revision=revision+1,updated_at=now() where invoice_id=p_id;
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'invoice_'||p_decision,jsonb_build_object('reason',p_note,'single_manager_workflow',true));return r;
end $$;

create or replace function private.record_exception(p_id uuid,p_secret text,p_plan text,p_engine text) returns jsonb language plpgsql security definer set search_path='' as $$
declare assessment jsonb; plan text; state text;
begin
 perform private.require_resource(p_id,'invoice');
 if auth.uid() is null or not exists(select 1 from private.settings where key='review_hash' and value=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'Server authorization required';end if;
 assessment:=private.assess_invoice(p_id);state:=case when (assessment->>'blocked')::boolean or (assessment->>'score')::integer>=25 then 'open' else 'resolved' end;
 select string_agg(x->>'next_action',E'\n') into plan from jsonb_array_elements(assessment->'signals') x;
 if p_engine='ai' and length(p_plan) between 10 and 2500 then plan:=p_plan;end if;
 plan:=coalesce(plan,'No blocking exception found. Review the supporting business context before a manager decision.');
 insert into public.exception_cases(invoice_id,status,assessment,plan,engine) values(p_id,state,assessment,plan,case when p_engine='ai' then 'ai' else 'rules' end) on conflict(invoice_id) do update set status=excluded.status,assessment=excluded.assessment,plan=excluded.plan,engine=excluded.engine,updated_at=now();
 insert into public.activity(invoice_id,actor_id,event,details) values(p_id,auth.uid(),'exception_triaged',jsonb_build_object('status',state,'assessment',assessment,'plan',plan,'engine',p_engine));
 return assessment;
end $$;
