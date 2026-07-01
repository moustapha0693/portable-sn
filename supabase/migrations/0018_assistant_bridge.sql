-- ============================================================================
-- 0018 : Assistant = simple compte boutique (numéro + PIN). Le propriétaire
-- ajoute un numéro ; l'assistant accède via le geste avec son mot de passe
-- boutique. Un compte Supabase "synthétique" est créé à la volée par l'Edge
-- Function (pont), sans email réel. Le propriétaire garde son compte réel.
-- ============================================================================

-- Type d'accès pour un numéro (utilisé par le geste côté boutique).
create or replace function public.admin_account_kind(p_phone text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when m.phone is null then null else jsonb_build_object(
      'kind', case when m.phone = '776964876' then 'owner' else 'assistant' end,
      'email', m.email) end
  from (select right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9) as ph) x
  left join public.admin_members m on m.phone = x.ph;
$$;
grant execute on function public.admin_account_kind(text) to anon, authenticated;

-- Vérifie numéro + PIN (compte boutique) + appartenance, avec verrou anti-brute-force.
-- Réservée au service_role (appelée par l'Edge Function du pont).
create or replace function public.assistant_verify(p_phone text, p_pin text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients; v_email text; v_new int;
begin
  p_phone := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9);
  select email into v_email from public.admin_members where phone = p_phone;
  if v_email is null then return jsonb_build_object('ok', false, 'error', 'Ce numéro n''a pas accès.'); end if;
  select * into v from public.comptes_clients
    where right(regexp_replace(phone, '\D', '', 'g'), 9) = p_phone;
  if not found then return jsonb_build_object('ok', false, 'error', 'Crée d''abord ton compte sur la boutique.'); end if;
  if v.locked_until is not null and v.locked_until > now() then
    return jsonb_build_object('ok', false, 'error', 'Trop de tentatives. Réessaie plus tard.');
  end if;
  if v.pin_hash <> extensions.crypt(p_pin, v.pin_hash) then
    v_new := v.failed_attempts + 1;
    if v_new >= 5 then
      update public.comptes_clients set failed_attempts = 0, locked_until = now() + interval '15 minutes' where id = v.id;
      return jsonb_build_object('ok', false, 'error', 'Trop de tentatives. Compte bloqué 15 minutes.');
    else
      update public.comptes_clients set failed_attempts = v_new where id = v.id;
      return jsonb_build_object('ok', false, 'error', 'Mot de passe incorrect.');
    end if;
  end if;
  update public.comptes_clients set failed_attempts = 0, locked_until = null where id = v.id;
  return jsonb_build_object('ok', true, 'email', v_email, 'phone', p_phone,
    'full_name', v.full_name, 'is_owner', (p_phone = '776964876'));
end; $$;
revoke execute on function public.assistant_verify(text, text) from public, anon, authenticated;

-- Ajouter un assistant : juste le numéro (+ nom). Le compte boutique doit exister.
drop function if exists public.admin_member_add(text, text, text);
create or replace function public.admin_member_add(p_phone text, p_label text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_phone text; v_email text; v_name text;
begin
  if not public.is_owner() then raise exception 'Réservé au propriétaire.'; end if;
  v_phone := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9);
  if length(v_phone) <> 9 then raise exception 'Numéro invalide (9 chiffres).'; end if;
  select full_name into v_name from public.comptes_clients
    where right(regexp_replace(phone, '\D', '', 'g'), 9) = v_phone;
  if v_name is null and not exists (select 1 from public.comptes_clients
      where right(regexp_replace(phone, '\D', '', 'g'), 9) = v_phone) then
    raise exception 'Cette personne doit d''abord créer son compte sur la boutique (numéro + mot de passe).';
  end if;
  v_email := 'psn-' || v_phone || '@assistant.portable.local';
  insert into public.admin_members(phone, email, label)
    values (v_phone, v_email, nullif(trim(p_label), ''))
    on conflict (phone) do update set label = excluded.label;
  return jsonb_build_object('ok', true, 'phone', v_phone);
end; $$;
grant execute on function public.admin_member_add(text, text) to authenticated;

-- Supprimer un assistant : retire aussi est_admin du compte lié (vraie révocation).
create or replace function public.admin_member_remove(p_phone text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_phone text; v_email text;
begin
  if not public.is_owner() then raise exception 'Réservé au propriétaire.'; end if;
  v_phone := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9);
  if v_phone = '776964876' then raise exception 'Impossible de supprimer le propriétaire.'; end if;
  select email into v_email from public.admin_members where phone = v_phone;
  if v_email is null then raise exception 'Numéro introuvable dans la liste.'; end if;
  update public.profiles set est_admin = false
    where id in (select id from auth.users where lower(email) = v_email);
  delete from public.admin_members where phone = v_phone;
  return jsonb_build_object('ok', true);
end; $$;
grant execute on function public.admin_member_remove(text) to authenticated;

-- Liste des accès (propriétaire) avec le nom du compte boutique lié.
create or replace function public.admin_member_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'Réservé au propriétaire.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('phone', m.phone, 'label', m.label,
             'added_at', m.added_at, 'is_owner', (m.phone = '776964876'),
             'name', c.full_name) order by m.added_at)
    from public.admin_members m
    left join public.comptes_clients c
      on right(regexp_replace(c.phone, '\D', '', 'g'), 9) = m.phone
  ), '[]'::jsonb);
end; $$;
grant execute on function public.admin_member_list() to authenticated;
