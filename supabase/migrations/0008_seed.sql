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

-- Zones de livraison : reprise des 14 régions de l'ancien schéma (zones_livraison).
insert into public.delivery_zones (name, fee, position, is_active) values
  ('Dakar',       0,    1,  true),
  ('Thiès',       2000, 2,  true),
  ('Saint-Louis', 3000, 3,  true),
  ('Diourbel',    2500, 4,  true),
  ('Louga',       3000, 5,  true),
  ('Fatick',      2500, 6,  true),
  ('Kaolack',     2500, 7,  true),
  ('Kaffrine',    3000, 8,  true),
  ('Tambacounda', 4000, 9,  true),
  ('Kédougou',    5000, 10, true),
  ('Kolda',       4000, 11, true),
  ('Sédhiou',     4000, 12, true),
  ('Ziguinchor',  4000, 13, true),
  ('Matam',       4000, 14, true)
on conflict (name) do nothing;

-- NOTE : après ta première inscription via Supabase Auth, exécuter :
--   update public.profiles set est_admin = true where id = '<ton-user-id>';
