-- Email-bound invitations can create or recover an employee account without relying on email delivery.
alter table private.company_invitations add column invited_email text;
alter table private.company_invitations add column reserved_by uuid references auth.users(id);
alter table private.company_invitations add column reserved_at timestamptz;

create or replace function private.create_company_invitation(p_email text) returns text
language plpgsql security definer set search_path='' as $$
declare code text; normalized text:=lower(btrim(p_email));
begin
 if not private.is_manager() then raise exception 'Manager two-factor authentication required';end if;
 if normalized !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(normalized)>254 then raise exception 'Enter a valid employee email address';end if;
 if (select count(*) from private.company_invitations where workspace_id=private.current_workspace() and expires_at>now() and used_at is null)>=20 then raise exception 'Use or revoke existing invitations first';end if;
 code:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into private.company_invitations(workspace_id,code_hash,created_by,expires_at,invited_email)
 values(private.current_workspace(),encode(extensions.digest(code,'sha256'),'hex'),auth.uid(),now()+interval '24 hours',normalized);
 insert into public.security_events(workspace_id,actor_id,event,details) values(private.current_workspace(),auth.uid(),'invitation_created',jsonb_build_object('invitee_email',normalized));
 return code;
end $$;
create function public.create_company_invitation(p_email text) returns text language sql security invoker set search_path='' as $$select private.create_company_invitation(p_email)$$;
revoke all on function public.create_company_invitation(text) from public,anon;
grant execute on function public.create_company_invitation(text) to authenticated;

create function private.validate_company_invitation_signup(p_code text,p_email text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Service authorization required';end if;
 return exists(select 1 from private.company_invitations where code_hash=encode(extensions.digest(p_code,'sha256'),'hex') and invited_email=lower(btrim(p_email)) and used_at is null and expires_at>now());
end $$;
create function public.validate_company_invitation_signup(p_code text,p_email text) returns boolean language sql security definer set search_path='' as $$select private.validate_company_invitation_signup(p_code,p_email)$$;
revoke all on function public.validate_company_invitation_signup(text,text) from public,anon,authenticated;
grant execute on function public.validate_company_invitation_signup(text,text) to service_role;

create function private.reserve_company_invitation_signup(p_code text,p_email text,p_user uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare inv private.company_invitations;
begin
 if auth.role()<>'service_role' then raise exception 'Service authorization required';end if;
 select * into inv from private.company_invitations where code_hash=encode(extensions.digest(p_code,'sha256'),'hex') and invited_email=lower(btrim(p_email)) and used_at is null and expires_at>now() for update;
 if not found or not exists(select 1 from auth.users where id=p_user and lower(email)=lower(btrim(p_email))) then return false;end if;
 if exists(select 1 from public.profiles where id=p_user and workspace_id is not null) then return false;end if;
 if inv.reserved_by is not null and inv.reserved_by<>p_user and inv.reserved_at>now()-interval '10 minutes' then return false;end if;
 update private.company_invitations set reserved_by=p_user,reserved_at=now() where id=inv.id;
 return true;
end $$;
create function public.reserve_company_invitation_signup(p_code text,p_email text,p_user uuid) returns boolean language sql security definer set search_path='' as $$select private.reserve_company_invitation_signup(p_code,p_email,p_user)$$;
revoke all on function public.reserve_company_invitation_signup(text,text,uuid) from public,anon,authenticated;
grant execute on function public.reserve_company_invitation_signup(text,text,uuid) to service_role;

create function private.accept_company_invitation_signup(p_code text,p_email text,p_user uuid,p_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare inv private.company_invitations; normalized text:=lower(btrim(p_email)); clean_name text:=btrim(p_name); assigned integer;
begin
 if auth.role()<>'service_role' then raise exception 'Service authorization required';end if;
 if length(clean_name) not between 2 and 80 then raise exception 'Use a name between 2 and 80 characters';end if;
 select * into inv from private.company_invitations where code_hash=encode(extensions.digest(p_code,'sha256'),'hex') and invited_email=normalized and reserved_by=p_user and reserved_at>now()-interval '10 minutes' and used_at is null and expires_at>now() for update;
 if not found or not exists(select 1 from auth.users where id=p_user and lower(email)=normalized and email_confirmed_at is not null) then raise exception 'Invitation expired, invalid, or already used';end if;
 insert into public.profiles(id,name,role,workspace_id) values(p_user,clean_name,'employee',inv.workspace_id)
 on conflict(id) do update set name=excluded.name,role='employee',workspace_id=excluded.workspace_id where public.profiles.workspace_id is null;
 get diagnostics assigned=row_count;
 if assigned<>1 then raise exception 'This account already belongs to a company';end if;
 update private.company_invitations set used_at=now(),reserved_by=null,reserved_at=null where id=inv.id;
 insert into public.security_events(workspace_id,actor_id,event,details) values(inv.workspace_id,p_user,'invitation_accepted',jsonb_build_object('invitee_email',normalized));
 return inv.workspace_id;
end $$;
create function public.accept_company_invitation_signup(p_code text,p_email text,p_user uuid,p_name text) returns uuid language sql security definer set search_path='' as $$select private.accept_company_invitation_signup(p_code,p_email,p_user,p_name)$$;
revoke all on function public.accept_company_invitation_signup(text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.accept_company_invitation_signup(text,text,uuid,text) to service_role;
revoke all on function private.validate_company_invitation_signup(text,text),private.reserve_company_invitation_signup(text,text,uuid),private.accept_company_invitation_signup(text,text,uuid,text) from public,anon,authenticated;
grant execute on function private.validate_company_invitation_signup(text,text),private.reserve_company_invitation_signup(text,text,uuid),private.accept_company_invitation_signup(text,text,uuid,text) to service_role;
