-- ============================================================================
-- 0012_comptes_clients.sql — Comptes clients (téléphone + mot de passe)
--
-- Authentification simple (sans OTP/SMS) : le client crée un mot de passe à
-- 6 chiffres, stocké HACHÉ (bcrypt via pgcrypto). Il peut se reconnecter avec
-- le même téléphone + mot de passe depuis n'importe quel navigateur.
--
-- La table est protégée par RLS sans policy : accès uniquement via les
-- fonctions RPC SECURITY DEFINER ci-dessous (le hash n'est jamais exposé).
-- ============================================================================

create table if not exists public.comptes_clients (
  id         bigint generated always as identity primary key,
  phone      text not null unique,          -- 9 chiffres (sans l'indicatif 221)
  pin_hash   text not null,                 -- hash bcrypt du mot de passe
  full_name  text,
  region     text,
  quartier   text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.comptes_clients enable row level security;

create or replace function public.inscription_client(
  p_phone text, p_pin text, p_full_name text, p_region text, p_quartier text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients;
begin
  if p_phone !~ '^[0-9]{9}$' then raise exception 'Numéro invalide (9 chiffres).'; end if;
  if p_pin !~ '^[0-9]{6}$' then raise exception 'Le mot de passe doit comporter 6 chiffres.'; end if;
  if exists (select 1 from public.comptes_clients where phone = p_phone) then
    raise exception 'Un compte existe déjà avec ce numéro.';
  end if;
  insert into public.comptes_clients (phone, pin_hash, full_name, region, quartier)
  values (p_phone, extensions.crypt(p_pin, extensions.gen_salt('bf')),
          nullif(trim(p_full_name), ''), nullif(trim(p_region), ''), nullif(trim(p_quartier), ''))
  returning * into v;
  return jsonb_build_object('phone', v.phone, 'full_name', v.full_name, 'region', v.region, 'quartier', v.quartier);
end; $$;

create or replace function public.connexion_client(p_phone text, p_pin text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients;
begin
  select * into v from public.comptes_clients where phone = p_phone;
  if not found or v.pin_hash <> extensions.crypt(p_pin, v.pin_hash) then
    raise exception 'Numéro ou mot de passe incorrect.';
  end if;
  return jsonb_build_object('phone', v.phone, 'full_name', v.full_name, 'region', v.region, 'quartier', v.quartier);
end; $$;

create or replace function public.maj_profil_client(
  p_phone text, p_full_name text, p_region text, p_quartier text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients;
begin
  update public.comptes_clients
     set full_name = nullif(trim(p_full_name), ''),
         region    = nullif(trim(p_region), ''),
         quartier  = nullif(trim(p_quartier), ''),
         updated_at = now()
   where phone = p_phone
   returning * into v;
  if not found then raise exception 'Compte introuvable.'; end if;
  return jsonb_build_object('phone', v.phone, 'full_name', v.full_name, 'region', v.region, 'quartier', v.quartier);
end; $$;

grant execute on function public.inscription_client(text,text,text,text,text) to anon, authenticated;
grant execute on function public.connexion_client(text,text) to anon, authenticated;
grant execute on function public.maj_profil_client(text,text,text,text) to anon, authenticated;
