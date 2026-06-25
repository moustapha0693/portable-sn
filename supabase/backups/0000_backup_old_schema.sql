-- ============================================================================
-- SAUVEGARDE — ancien schéma portable-sn (snapshot avant suppression)
--
-- Copie de sécurité des SEULES tables contenant des données :
--   - admins  (SANS le champ "password", volontairement exclu)
--   - categories
--   - zones_livraison
--
-- Tables vides au moment de la sauvegarde (donc non incluses) :
--   clients, commandes, commandes_client, produits
--
-- Restauration : exécuter ce fichier sur une base où ces tables n'existent pas
-- (les noms sont suffixés _backup pour ne JAMAIS écraser le schéma courant).
-- Données figées le : inspection en lecture seule (option A).
-- ============================================================================

begin;

-- ---- admins (sans password) ----------------------------------------------
create table if not exists public.admins_backup (
  id         integer primary key,
  nom        text not null,
  role       integer,
  created_by integer,
  active     boolean
);
insert into public.admins_backup (id, nom, role, created_by, active) values
  (1, 'Admin 2',      2, 1, true),
  (2, 'Gestionnaire', 2, 1, true),
  (3, 'Gestionnaire', 2, 1, true);

-- ---- categories ----------------------------------------------------------
create table if not exists public.categories_backup (
  id      integer primary key,
  nom     text not null,
  ordre   integer,
  visible boolean,
  emoji   text
);
insert into public.categories_backup (id, nom, ordre, visible, emoji) values
  (1, 'Smartphones', 1, true, '📱'),
  (2, 'iPhone',      2, true, '📱'),
  (3, 'Samsung',     3, true, '📱'),
  (4, 'Android',     4, true, '📱'),
  (5, 'Accessoires', 5, true, '📱');

-- ---- zones_livraison -----------------------------------------------------
create table if not exists public.zones_livraison_backup (
  id      integer primary key,
  nom     text not null,
  prix    integer,
  gratuit boolean
);
insert into public.zones_livraison_backup (id, nom, prix, gratuit) values
  (1,  'Dakar',       0,    true),
  (2,  'Thiès',       2000, false),
  (3,  'Saint-Louis', 3000, false),
  (4,  'Diourbel',    2500, false),
  (5,  'Louga',       3000, false),
  (6,  'Fatick',      2500, false),
  (7,  'Kaolack',     2500, false),
  (8,  'Kaffrine',    3000, false),
  (9,  'Tambacounda', 4000, false),
  (10, 'Kédougou',    5000, false),
  (11, 'Kolda',       4000, false),
  (12, 'Sédhiou',     4000, false),
  (13, 'Ziguinchor',  4000, false),
  (14, 'Matam',       4000, false);

commit;
