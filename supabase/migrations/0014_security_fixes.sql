-- ============================================================================
-- 0014_security_fixes.sql — Correctifs de sécurité (audit avant déploiement)
--
-- 1) maj_profil_client : la version par p_phone permettait à n'importe qui de
--    modifier le profil (nom/région/quartier) d'un autre client sans être
--    authentifié. On exige désormais le jeton de session (session_token).
-- 2) Bucket public "produits" : retrait de la policy SELECT qui autorisait le
--    LISTING de tous les fichiers. L'accès aux images par URL publique reste OK.
-- ============================================================================

drop function if exists public.maj_profil_client(text, text, text, text);

create or replace function public.maj_profil_client(p_token text, p_full_name text, p_region text, p_quartier text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients;
begin
  if p_token is null or p_token = '' then raise exception 'Non connecté.'; end if;
  update public.comptes_clients
     set full_name = nullif(trim(p_full_name), ''),
         region    = nullif(trim(p_region), ''),
         quartier  = nullif(trim(p_quartier), ''),
         updated_at = now()
   where session_token = p_token
   returning * into v;
  if not found then raise exception 'Session expirée, reconnecte-toi.'; end if;
  return jsonb_build_object('phone', v.phone, 'full_name', v.full_name, 'region', v.region, 'quartier', v.quartier);
end; $$;

grant execute on function public.maj_profil_client(text, text, text, text) to anon, authenticated;

drop policy if exists "produits_read" on storage.objects;
