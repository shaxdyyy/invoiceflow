create or replace function private.finish_document_read(p_id uuid,p_run_id uuid,p_secret text,p_data jsonb,p_text text,p_hash text,p_engine text,p_error text default '') returns public.documents language plpgsql security definer set search_path='' as $$
declare d public.documents;
begin
 perform private.require_resource(p_id,'document');
 perform private.authorize_document_server(p_secret);
 select * into d from public.documents where id=p_id and (owner_id=auth.uid() or private.is_manager()) for update;
 if not found or d.status<>'extracting' or d.run_id is distinct from p_run_id or d.extracted is not null then raise exception 'Stale document read';end if;
 if p_error<>'' then update public.documents set status='failed',error=left(p_error,1000),updated_at=now() where id=p_id returning * into d;return d;end if;
 if length(p_text)>24000 or length(p_data::text)>40000 or p_hash!~'^[a-f0-9]{64}$' or p_engine not in ('groq','gemini','azure','demo','local-text') or jsonb_typeof(p_data->'uncertainties') is distinct from 'array' then raise exception 'Invalid extraction snapshot';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_hash,34));
 update public.documents set extracted=p_data,source_text=p_text,content_hash=p_hash,engine=p_engine,review_state=case when jsonb_array_length(p_data->'uncertainties')>0 then 'needs_input' else 'ready' end,status=case when jsonb_array_length(p_data->'uncertainties')>0 then 'needs_input' else 'extracted' end,error=null,updated_at=now() where id=p_id returning * into d;
 return d;
end $$;
