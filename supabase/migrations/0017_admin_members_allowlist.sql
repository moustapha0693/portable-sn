-- ============================================================================
-- 0017 : Liste des accès admin gérée par le propriétaire (numéro -> compte).
--  - profiles.is_owner : un seul propriétaire (776964876 / moustapha0693).
--  - admin_members : numéros autorisés, chacun lié à un compte Supabase (email).
--  - Seul le propriétaire peut ajouter/supprimer ; supprimer retire est_admin.
--  - guard renforcé : seul le propriétaire peut changer role/est_admin/is_owner.
-- ============================================================================

alter table public.profiles add column if not exists is_owner boolean not null default false;

create table if not exists public.admin_members (
  phone text primary key,
  email text not null,
  label text,
  added_at timestamptz not null default now()
);
alter table public.admin_members enable row level security; -- aucun accès direct : RPC uniquement

-- Propriétaire = moustapha0693@gmail.com / 776964876
update public.profiles p set is_owner = true, est_admin = true
from auth.users u where u.id = p.id and lower(u.email) = 'moustapha0693@gmail.com';

insert into public.admin_members(phone, email, label)
select '776964876', lower(u.email), 'Propriétaire'
from auth.users u where lower(u.email) = 'moustapha0693@gmail.com'
on conflict (phone) do nothing;

-- Est-ce le propriétaire connecté ?
create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles where id = auth.uid() and is_owner = true);
$$;
grant execute on function public.is_owner() to authenticated;

-- Garde renforcée : seul le propriétaire modifie role / est_admin / is_owner.
create or replace function public.guard_profile_role()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_owner() then
    if tg_op = 'INSERT' then
      new.role := 'client'; new.est_admin := false; new.is_owner := false;
    else
      new.role := old.role; new.est_admin := old.est_admin; new.is_owner := old.is_owner;
    end if;
  end if;
  return new;
end; $$;

-- Liste des accès (propriétaire uniquement)
create or replace function public.admin_member_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'Réservé au propriétaire.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('phone', m.phone, 'email', m.email,
             'label', m.label, 'added_at', m.added_at,
             'is_owner', coalesce(p.is_owner, false)) order by m.added_at)
    from public.admin_members m
    left join auth.users u on lower(u.email) = m.email
    left join public.profiles p on p.id = u.id
  ), '[]'::jsonb);
end; $$;
grant execute on function public.admin_member_list() to authenticated;

-- Ajouter un accès : numéro -> compte Supabase existant ; accorde est_admin.
create or replace function public.admin_member_add(p_phone text, p_email text, p_label text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid; v_phone text; v_email text;
begin
  if not public.is_owner() then raise exception 'Réservé au propriétaire.'; end if;
  v_phone := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9);
  if length(v_phone) <> 9 then raise exception 'Numéro invalide (9 chiffres).'; end if;
  v_email := lower(trim(coalesce(p_email,'')));
  if v_email = '' then raise exception 'Email requis.'; end if;
  select id into v_uid from auth.users where lower(email) = v_email;
  if v_uid is null then
    raise exception 'Aucun compte Supabase avec cet email. Crée-le d''abord (Authentication > Add user).';
  end if;
  insert into public.admin_members(phone, email, label)
    values (v_phone, v_email, nullif(trim(p_label), ''))
    on conflict (phone) do update set email = excluded.email, label = excluded.label;
  update public.profiles set est_admin = true where id = v_uid;
  return jsonb_build_object('ok', true, 'phone', v_phone, 'email', v_email);
end; $$;
grant execute on function public.admin_member_add(text, text, text) to authenticated;

-- Supprimer un accès : retire est_admin (vraie révocation). Interdit sur le propriétaire.
create or replace function public.admin_member_remove(p_phone text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_phone text; v_email text; v_uid uuid; v_owner boolean;
begin
  if not public.is_owner() then raise exception 'Réservé au propriétaire.'; end if;
  v_phone := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9);
  select email into v_email from public.admin_members where phone = v_phone;
  if v_email is null then raise exception 'Numéro introuvable dans la liste.'; end if;
  select u.id, coalesce(p.is_owner, false) into v_uid, v_owner
  from auth.users u left join public.profiles p on p.id = u.id
  where lower(u.email) = v_email;
  if v_owner then raise exception 'Impossible de supprimer le propriétaire.'; end if;
  if v_uid is not null then update public.profiles set est_admin = false where id = v_uid; end if;
  delete from public.admin_members where phone = v_phone;
  return jsonb_build_object('ok', true);
end; $$;
grant execute on function public.admin_member_remove(text) to authenticated;

-- Pour le geste : renvoie l'email lié à un numéro autorisé (sinon null).
create or replace function public.admin_login_email(p_phone text)
returns text language sql stable security definer set search_path = '' as $$
  select email from public.admin_members
  where phone = right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9);
$$;
grant execute on function public.admin_login_email(text) to anon, authenticated;
