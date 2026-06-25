-- ============================================================================
-- 0008_seed.sql — Données initiales
--
-- Dépendances : 0002 (tables). Exécuté en tant que propriétaire (postgres) lors
-- de la migration → contourne le RLS de 0006. Idempotent (on conflict).
-- ============================================================================
insert into public.settings (id, store_name, currency, color_primary, color_accent)
values (1, 'portable.sn', 'FCFA', '#2563eb', '#16a34a')
on conflict (id) do nothing;

insert into public.categories (slug, name, position) values
  ('telephones',   'Téléphones',   1),
  ('accessoires',  'Accessoires',  2),
  ('electronique', 'Électronique', 3),
  ('divers',       'Divers',       4)
on conflict (slug) do nothing;

-- NOTE : après ta première inscription via Supabase Auth, exécuter :
--   update public.profiles set est_admin = true where id = '<ton-user-id>';
