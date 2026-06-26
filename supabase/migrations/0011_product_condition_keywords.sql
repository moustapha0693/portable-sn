-- ============================================================================
-- 0011_product_condition_keywords.sql — Attributs produit supplémentaires
--
-- Ajoute l'état du produit et les mots-clés SEO sur public.products.
--   * condition : Neuf | Occasion | Reconditionné (défaut Neuf)
--   * keywords  : mots-clés / tags pour le référencement (texte libre)
-- ============================================================================

alter table public.products
  add column if not exists condition text not null default 'Neuf'
    check (condition in ('Neuf', 'Occasion', 'Reconditionné')),
  add column if not exists keywords text;
