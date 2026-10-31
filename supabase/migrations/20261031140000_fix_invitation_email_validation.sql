-- Use a character class for the email dot so SQL and regex string escaping cannot reject valid addresses.
create or replace function private.create_company_invitation(p_email text) returns text
language plpgsql security definer set search_path='' as $$
declare code text; normalized text:=lower(btrim(p_email));
begin
 if not private.is_manager() then raise exception 'Manager two-factor authentication required';end if;
 if normalized is null or normalized !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or length(normalized)>254 then raise exception 'Enter a valid employee email address';end if;
 if (select count(*) from private.company_invitations where workspace_id=private.current_workspace() and expires_at>now() and used_at is null)>=20 then raise exception 'Use or revoke existing invitations first';end if;
 code:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into private.company_invitations(workspace_id,code_hash,created_by,expires_at,invited_email)
 values(private.current_workspace(),encode(extensions.digest(code,'sha256'),'hex'),auth.uid(),now()+interval '24 hours',normalized);
 insert into public.security_events(workspace_id,actor_id,event,details) values(private.current_workspace(),auth.uid(),'invitation_created',jsonb_build_object('invitee_email',normalized));
 return code;
end $$;
