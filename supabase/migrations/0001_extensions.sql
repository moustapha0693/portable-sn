-- ============================================================================
-- 0001_extensions.sql — Objets fondateurs (prérequis de tout le reste)
--
-- Contient : extensions, types ENUM et séquence.
-- Dépendances : aucune.
-- Requis par : 0002 (enums utilisés par les tables), 0003 (opclass pg_trgm),
--              0007 (séquence order_ref_seq utilisée par la RPC).
--
-- Note de découpage : les ENUM et la séquence sont placés ici (et non dans
-- 0002_tables) car ce sont des prérequis de la création des tables et de la
-- RPC. Le contenu est identique à la migration monolithique d'origine.
-- ============================================================================

-- ========================= EXTENSIONS =======================================
-- Convention Supabase : les extensions vont dans le schéma "extensions".
create extension if not exists pg_trgm with schema extensions;

-- ========================= ENUMS ============================================
create type public.order_status        as enum
  ('en_attente','confirmee','en_livraison','livree','annulee');
create type public.stock_movement_type as enum
  ('entree','sortie','ajustement','vente','retour');
create type public.discount_type       as enum
  ('percent','fixed');

-- ========================= SÉQUENCES ========================================
create sequence if not exists public.order_ref_seq;   -- numérotation des commandes
