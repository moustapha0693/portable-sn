-- ============================================================================
-- 0006_rls.sql — Activation RLS + policies
--
-- Dépendances : 0002 (tables) + 0004 (public.is_admin()).
-- Indépendant de 0005 (triggers) et 0007 (RPC).
-- is_admin() et auth.uid() encapsulés dans (select ...) → évalués une fois par
-- requête (init-plan) plutôt qu'à chaque ligne.
-- ============================================================================

-- ----------------------------- ACTIVATION ----------------------------------
alter table public.settings             enable row level security;
alter table public.banners              enable row level security;
alter table public.categories           enable row level security;
alter table public.products             enable row level security;
alter table public.product_variants     enable row level security;
alter table public.product_images       enable row level security;
alter table public.profiles             enable row level security;
alter table public.favorites            enable row level security;
alter table public.coupons              enable row level security;
alter table public.delivery_zones       enable row level security;
alter table public.orders               enable row level security;
alter table public.stock_movements      enable row level security;
alter table public.coupon_redemptions   enable row level security;
alter table public.order_items          enable row level security;
alter table public.reviews              enable row level security;
alter table public.order_status_history enable row level security;

-- ------------------------------- POLICIES -----------------------------------

-- settings : lecture publique (config front), écriture admin
create policy settings_read  on public.settings for select to anon, authenticated using (true);
create policy settings_admin on public.settings for all    to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- banners : visibles si actives et dans la fenêtre de dates (ou admin)
create policy banners_read  on public.banners for select to anon, authenticated using (
  (select public.is_admin()) or (
    is_active
    and (starts_at is null or starts_at <= now())
    and (ends_at   is null or ends_at   >= now())
  ));
create policy banners_admin on public.banners for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- categories : lecture publique des actives, écriture admin
create policy categories_read  on public.categories for select to anon, authenticated
  using (is_active or (select public.is_admin()));
create policy categories_admin on public.categories for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- products : lecture publique des actifs, écriture admin
create policy products_read  on public.products for select to anon, authenticated
  using (is_active or (select public.is_admin()));
create policy products_admin on public.products for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- product_variants : visibles si actives et produit actif (ou admin)
create policy variants_read  on public.product_variants for select to anon, authenticated using (
  (select public.is_admin()) or (
    is_active and exists (select 1 from public.products p
                          where p.id = product_id and p.is_active)
  ));
create policy variants_admin on public.product_variants for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- product_images : visibles si produit actif (ou admin)
create policy images_read  on public.product_images for select to anon, authenticated using (
  (select public.is_admin()) or exists (select 1 from public.products p
                                         where p.id = product_id and p.is_active)
  );
create policy images_admin on public.product_images for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- profiles : chacun le sien (+ admin). role/est_admin protégés par trg_guard_profile.
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()))
  with check (id = (select auth.uid()) or (select public.is_admin()));

-- favorites : chacun les siens (+ lecture admin)
create policy favorites_select on public.favorites for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy favorites_write  on public.favorites for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- coupons : non exposés au public (validés via RPC), gérés par admin
create policy coupons_admin on public.coupons for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- delivery_zones : lecture publique des zones actives, écriture admin
create policy delivery_zones_read  on public.delivery_zones for select to anon, authenticated
  using (is_active or (select public.is_admin()));
create policy delivery_zones_admin on public.delivery_zones for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- stock_movements : admin uniquement (écritures aussi via RPC/triggers en definer)
create policy stock_admin on public.stock_movements for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- coupon_redemptions : son historique (+ admin) ; écriture via RPC uniquement
create policy redemptions_select on public.coupon_redemptions for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- orders : lecture de ses commandes (+ admin). Aucune insertion directe (RPC).
create policy orders_select on public.orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy orders_admin_update on public.orders for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy orders_admin_delete on public.orders for delete to authenticated
  using ((select public.is_admin()));

-- order_items : visibles via la commande possédée (+ admin). Insertion via RPC.
create policy order_items_select on public.order_items for select to authenticated using (
  exists (select 1 from public.orders o
          where o.id = order_id and (o.user_id = (select auth.uid()) or (select public.is_admin())))
  );

-- reviews : lecture des avis approuvés (ou les siens / admin).
-- Un client gère ses avis mais NE PEUT PAS s'auto-approuver (is_approved forcé à false).
create policy reviews_select on public.reviews for select to anon, authenticated
  using (is_approved or user_id = (select auth.uid()) or (select public.is_admin()));
create policy reviews_insert on public.reviews for insert to authenticated
  with check (
    (user_id = (select auth.uid()) and is_approved = false) or (select public.is_admin())
  );
create policy reviews_update on public.reviews for update to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (
    (user_id = (select auth.uid()) and is_approved = false) or (select public.is_admin())
  );
create policy reviews_delete on public.reviews for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- order_status_history : lecture via la commande possédée (+ admin). Écriture via trigger.
create policy osh_select on public.order_status_history for select to authenticated using (
  exists (select 1 from public.orders o
          where o.id = order_id and (o.user_id = (select auth.uid()) or (select public.is_admin())))
  );
