-- Accorde est_admin au compte lié à un email (appelée par l'Edge Function, service_role).
create or replace function public.admin_grant_by_email(p_email text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid;
begin
  select id into v_uid from auth.users where lower(email) = lower(coalesce(p_email,''));
  if v_uid is null then return false; end if;
  update public.profiles set est_admin = true where id = v_uid;
  return true;
end; $$;
revoke execute on function public.admin_grant_by_email(text) from public, anon, authenticated;
