-- ============================================================================
-- 0003_indexes.sql — Index
--
-- Dépendances : 0002 (tables) et 0001 (opclass extensions.gin_trgm_ops).
-- Requis par : rien (optimisation pure ; n'altère pas le comportement).
-- ============================================================================
create index idx_products_category  on public.products(category_id);
create index idx_products_brand      on public.products(brand);
create index idx_products_active     on public.products(is_active) where is_active;
create index idx_products_name_trgm  on public.products using gin (name extensions.gin_trgm_ops);

create index idx_categories_parent   on public.categories(parent_id);
create index idx_variants_product    on public.product_variants(product_id);
create index idx_images_product      on public.product_images(product_id);
create index idx_images_variant      on public.product_images(variant_id);
create index idx_stock_variant       on public.stock_movements(variant_id);
create index idx_stock_order         on public.stock_movements(order_id);
create index idx_favorites_product   on public.favorites(product_id);

create index idx_orders_user         on public.orders(user_id);
create index idx_orders_status       on public.orders(status);
create index idx_orders_created      on public.orders(created_at desc);
create index idx_orders_coupon       on public.orders(coupon_id);
create index idx_orders_phone_recent on public.orders(customer_phone, created_at desc); -- anti-spam RPC
create index idx_order_items_order   on public.order_items(order_id);
create index idx_order_items_variant on public.order_items(variant_id);
create index idx_order_items_product on public.order_items(product_id);

create index idx_redemptions_coupon  on public.coupon_redemptions(coupon_id);
create index idx_redemptions_order   on public.coupon_redemptions(order_id);
create index idx_redemptions_user    on public.coupon_redemptions(user_id);
create index idx_reviews_product     on public.reviews(product_id) where is_approved;
create index idx_reviews_user        on public.reviews(user_id);
create index idx_reviews_order       on public.reviews(order_id);
create index idx_osh_order           on public.order_status_history(order_id);
create index idx_banners_active      on public.banners(is_active, position);
