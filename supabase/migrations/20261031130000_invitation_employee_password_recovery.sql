-- Let an email-bound manager invitation recover an employee account only within that same company.
create or replace function private.reserve_company_invitation_signup(p_code text,p_email text,p_user uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare inv private.company_invitations; member public.profiles;
begin
 if auth.role()<>'service_role' then raise exception 'Service authorization required';end if;
 select * into inv from private.company_invitations where code_hash=encode(extensions.digest(p_code,'sha256'),'hex') and invited_email=lower(btrim(p_email)) and used_at is null and expires_at>now() for update;
 if not found or not exists(select 1 from auth.users where id=p_user and lower(email)=lower(btrim(p_email))) then return false;end if;
 select * into member from public.profiles where id=p_user;
 if found and member.workspace_id is not null and (member.workspace_id<>inv.workspace_id or member.role<>'employee') then return false;end if;
 if inv.reserved_by is not null and inv.reserved_by<>p_user and inv.reserved_at>now()-interval '10 minutes' then return false;end if;
 update private.company_invitations set reserved_by=p_user,reserved_at=now() where id=inv.id;
 return true;
end $$;
create or replace function private.accept_company_invitation_signup(p_code text,p_email text,p_user uuid,p_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare inv private.company_invitations; normalized text:=lower(btrim(p_email)); clean_name text:=btrim(p_name); assigned integer;
begin
 if auth.role()<>'service_role' then raise exception 'Service authorization required';end if;
 if length(clean_name) not between 2 and 80 then raise exception 'Use a name between 2 and 80 characters';end if;
 select * into inv from private.company_invitations where code_hash=encode(extensions.digest(p_code,'sha256'),'hex') and invited_email=normalized and reserved_by=p_user and reserved_at>now()-interval '10 minutes' and used_at is null and expires_at>now() for update;
 if not found or not exists(select 1 from auth.users where id=p_user and lower(email)=normalized and email_confirmed_at is not null) then raise exception 'Invitation expired, invalid, or already used';end if;
 insert into public.profiles(id,name,role,workspace_id) values(p_user,clean_name,'employee',inv.workspace_id)
 on conflict(id) do update set name=excluded.name,role='employee',workspace_id=excluded.workspace_id where public.profiles.workspace_id is null or (public.profiles.workspace_id=excluded.workspace_id and public.profiles.role='employee');
 get diagnostics assigned=row_count;
 if assigned<>1 then raise exception 'This account cannot be recovered with this company invitation';end if;
 update private.company_invitations set used_at=now(),reserved_by=null,reserved_at=null where id=inv.id;
 insert into public.security_events(workspace_id,actor_id,event,details) values(inv.workspace_id,p_user,'invitation_accepted',jsonb_build_object('invitee_email',normalized,'recovered_existing_account',true));
 return inv.workspace_id;
end $$;
revoke all on function private.reserve_company_invitation_signup(text,text,uuid),private.accept_company_invitation_signup(text,text,uuid,text) from public,anon,authenticated;
grant execute on function private.reserve_company_invitation_signup(text,text,uuid),private.accept_company_invitation_signup(text,text,uuid,text) to service_role;
