-- ============================================================================
-- 0009_security_hardening.sql — Durcissement
--
-- 1) Révoque EXECUTE sur les fonctions de TRIGGER (jamais appelées directement).
--    Les triggers continuent de fonctionner : PostgreSQL n'exige PAS le
--    privilège EXECUTE sur la fonction de trigger pour l'utilisateur qui
--    déclenche l'opération. is_admin() et passer_commande() ne sont PAS touchées
--    (is_admin est requise par les policies ; passer_commande est l'API publique).
--
-- 2) Corrige guard_profile_role : ne clamper role/est_admin que pour un
--    utilisateur FINAL authentifié non-admin. Les contextes de confiance
--    (service_role / postgres : SQL editor, migrations, bootstrap du 1er admin
--    où auth.uid() IS NULL) restent autorisés à fixer ces colonnes.
-- ============================================================================

revoke execute on function public.set_updated_at()        from public, anon, authenticated;
revoke execute on function public.handle_new_user()        from public, anon, authenticated;
revoke execute on function public.guard_profile_role()     from public, anon, authenticated;
revoke execute on function public.apply_stock_movement()   from public, anon, authenticated;
revoke execute on function public.refresh_product_cache()  from public, anon, authenticated;
revoke execute on function public.refresh_product_rating() from public, anon, authenticated;
revoke execute on function public.log_order_status()       from public, anon, authenticated;

create or replace function public.guard_profile_role()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.role := 'client';
      new.est_admin := false;
    else
      new.role := old.role;
      new.est_admin := old.est_admin;
    end if;
  end if;
  return new;
end; $$;

-- Re-révoque après le CREATE OR REPLACE (qui restaure le grant par défaut à PUBLIC).
revoke execute on function public.guard_profile_role() from public, anon, authenticated;
