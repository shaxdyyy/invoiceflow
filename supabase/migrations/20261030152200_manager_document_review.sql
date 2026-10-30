-- Upload-first source integrity; a single manager may correct and approve, with an immutable audit trail.
alter table public.documents add column source_text text,add column snapshot_origin text not null default 'extracted',add column content_hash text,add column review_data jsonb,add column revision integer not null default 0,add column review_state text not null default 'pending' check(review_state in ('pending','needs_input','ready','approved','rejected'));
alter table public.documents alter column created_at set default clock_timestamp();
create index document_content_hash on public.documents(content_hash) where content_hash is not null;
create table public.document_audit(id uuid primary key default gen_random_uuid(),document_id uuid not null references public.documents(id),actor_id uuid not null references public.profiles(id),action text not null,reason text not null,before_data jsonb,after_data jsonb,revision integer not null,created_at timestamptz not null default now());
alter table public.document_audit enable row level security;
revoke all on public.document_audit from public,anon,authenticated;grant select on public.document_audit to authenticated;
create index document_audit_document on public.document_audit(document_id,created_at);
create index document_audit_actor on public.document_audit(actor_id);
create policy document_audit_read on public.document_audit for select to authenticated using(exists(select 1 from public.documents d where d.id=document_id and (d.owner_id=(select auth.uid()) or (select private.is_manager()))));

create function private.authorize_document_server(p_secret text) returns void language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not exists(select 1 from private.settings where key='review_hash' and value=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'Server authorization required';end if;
end $$;
revoke all on function private.authorize_document_server(text) from public,anon,authenticated;
create function private.start_document_read(p_id uuid,p_secret text,p_ai boolean) returns public.documents language plpgsql security definer set search_path='' as $$
declare d public.documents;
begin
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
create function private.finish_document_read(p_id uuid,p_run_id uuid,p_secret text,p_data jsonb,p_text text,p_hash text,p_engine text,p_error text default '') returns public.documents language plpgsql security definer set search_path='' as $$
declare d public.documents;
begin
 perform private.authorize_document_server(p_secret);
 select * into d from public.documents where id=p_id and (owner_id=auth.uid() or private.is_manager()) for update;
 if not found or d.status<>'extracting' or d.run_id is distinct from p_run_id or d.extracted is not null then raise exception 'Stale document read';end if;
 if p_error<>'' then update public.documents set status='failed',error=left(p_error,1000),updated_at=now() where id=p_id returning * into d;return d;end if;
 if length(p_text)>24000 or length(p_data::text)>40000 or p_hash!~'^[a-f0-9]{64}$' or p_engine not in ('gemini','local-text') or jsonb_typeof(p_data->'uncertainties') is distinct from 'array' then raise exception 'Invalid extraction snapshot';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_hash,34));
 update public.documents set extracted=p_data,source_text=p_text,content_hash=p_hash,engine=p_engine,review_state=case when jsonb_array_length(p_data->'uncertainties')>0 then 'needs_input' else 'ready' end,status=case when jsonb_array_length(p_data->'uncertainties')>0 then 'needs_input' else 'extracted' end,error=null,updated_at=now() where id=p_id returning * into d;
 return d;
end $$;
-- Internal helper: never accepts employee-supplied invoice facts. Called only by server commit or manager review.
create function private.write_document_invoice(p_id uuid,p_input jsonb) returns public.invoices language plpgsql security definer set search_path='' as $$
declare d public.documents;r public.invoices;expected numeric;valid boolean;v_checks jsonb;
begin
 select * into d from public.documents where id=p_id for update;
 if d.extracted is null or d.review_state in ('approved','rejected') then raise exception 'Document is not available for review';end if;
 perform private.validate_input(p_input);
 if coalesce(p_input->>'currency','')<>'INR' then raise exception 'Only INR invoices may be reviewed';end if;
 if d.content_hash is not null then
 perform pg_advisory_xact_lock(hashtextextended(d.content_hash,34));
 if exists(select 1 from public.documents x left join public.invoices i on i.id=x.invoice_id where x.id<>d.id and x.content_hash=d.content_hash and x.review_state<>'rejected' and coalesce(i.status,'')<>'rejected' and (x.invoice_id is not null or x.created_at<d.created_at or (x.created_at=d.created_at and x.id<d.id))) then raise exception 'Duplicate document: this original has already been uploaded. Review or reject the earlier copy.';end if;end if;
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
revoke all on function private.write_document_invoice(uuid,jsonb) from public,anon,authenticated;
create function private.commit_document(p_id uuid,p_secret text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.documents;r public.invoices;a jsonb;
begin
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
-- Single-manager decisions. No second-manager or self-approval restriction; every decision is audited.
create or replace function private.decide_invoice(p_id uuid,p_decision text,p_note text) returns public.invoices language plpgsql security definer set search_path='' as $$
declare r public.invoices;a jsonb;
begin
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
create function private.review_document(p_id uuid,p_revision integer,p_input jsonb,p_reason text,p_action text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.documents;r public.invoices;a jsonb;next_revision integer;before_data jsonb;
begin
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
-- Disable old client-write paths, including the old extraction completion/linking APIs.
revoke execute on function public.create_invoice(jsonb,uuid),private.create_invoice(jsonb,uuid),public.amend_invoice(uuid,jsonb),private.amend_invoice(uuid,jsonb),public.link_document(uuid,uuid,text),private.link_document(uuid,uuid,text),public.finish_extraction(uuid,uuid,text,jsonb,text),private.finish_extraction(uuid,uuid,text,jsonb,text) from authenticated;

revoke all on function private.start_document_read(uuid,text,boolean) from public,anon;
grant execute on function private.start_document_read(uuid,text,boolean) to authenticated;
create function public.start_document_read(p_id uuid,p_secret text,p_ai boolean) returns public.documents language sql security invoker set search_path='' as $$select private.start_document_read(p_id,p_secret,p_ai)$$;
revoke all on function public.start_document_read(uuid,text,boolean) from public,anon;
grant execute on function public.start_document_read(uuid,text,boolean) to authenticated;

revoke all on function private.finish_document_read(uuid,uuid,text,jsonb,text,text,text,text) from public,anon;
grant execute on function private.finish_document_read(uuid,uuid,text,jsonb,text,text,text,text) to authenticated;
create function public.finish_document_read(p_id uuid,p_run_id uuid,p_secret text,p_data jsonb,p_text text,p_hash text,p_engine text,p_error text default '') returns public.documents language sql security invoker set search_path='' as $$select private.finish_document_read(p_id,p_run_id,p_secret,p_data,p_text,p_hash,p_engine,p_error)$$;
revoke all on function public.finish_document_read(uuid,uuid,text,jsonb,text,text,text,text) from public,anon;
grant execute on function public.finish_document_read(uuid,uuid,text,jsonb,text,text,text,text) to authenticated;

revoke all on function private.commit_document(uuid,text) from public,anon;
grant execute on function private.commit_document(uuid,text) to authenticated;
create function public.commit_document(p_id uuid,p_secret text) returns jsonb language sql security invoker set search_path='' as $$select private.commit_document(p_id,p_secret)$$;
revoke all on function public.commit_document(uuid,text) from public,anon;
grant execute on function public.commit_document(uuid,text) to authenticated;

revoke all on function private.review_document(uuid,integer,jsonb,text,text) from public,anon;
grant execute on function private.review_document(uuid,integer,jsonb,text,text) to authenticated;
create function public.review_document(p_id uuid,p_revision integer,p_input jsonb,p_reason text,p_action text) returns jsonb language sql security invoker set search_path='' as $$select private.review_document(p_id,p_revision,p_input,p_reason,p_action)$$;
revoke all on function public.review_document(uuid,integer,jsonb,text,text) from public,anon;
grant execute on function public.review_document(uuid,integer,jsonb,text,text) to authenticated;

update public.documents d set review_state=case when i.status in ('approved','rejected') then i.status when d.extracted is null or jsonb_array_length(coalesce(d.extracted->'uncertainties','[]'))>0 then 'needs_input' else 'ready' end from public.invoices i where d.invoice_id=i.id;

-- Preserve access to prior uploaded originals, clearly labelling values imported from the previous workflow.
update public.documents d set snapshot_origin='legacy_import',extracted=jsonb_build_object('supplier',i.supplier,'invoice_number',i.invoice_number,'invoice_date',i.invoice_date,'due_date',i.due_date,'currency','INR','category',i.category,'items',i.items,'tax',i.tax,'total',i.total,'notes',i.notes,'uncertainties',jsonb_build_array('Legacy values were imported from the previous workflow. Compare the unchanged original before deciding.')),review_state=case when i.status in ('approved','rejected') then i.status else 'needs_input' end from public.invoices i where d.invoice_id=i.id and d.extracted is null;
