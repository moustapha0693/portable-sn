-- ============================================================================
-- 0005_triggers.sql — Triggers
--
-- Dépendances : 0002 (tables) + 0004 (fonctions de trigger référencées ici).
-- Requis par : rien.
-- ============================================================================
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create trigger trg_guard_profile before insert or update on public.profiles
  for each row execute function public.guard_profile_role();

create trigger trg_settings_updated  before update on public.settings
  for each row execute function public.set_updated_at();
create trigger trg_products_updated  before update on public.products
  for each row execute function public.set_updated_at();
create trigger trg_variants_updated  before update on public.product_variants
  for each row execute function public.set_updated_at();
create trigger trg_orders_updated    before update on public.orders
  for each row execute function public.set_updated_at();
create trigger trg_coupons_updated   before update on public.coupons
  for each row execute function public.set_updated_at();
create trigger trg_delivery_zones_updated before update on public.delivery_zones
  for each row execute function public.set_updated_at();

create trigger trg_stock_movement after insert on public.stock_movements
  for each row execute function public.apply_stock_movement();

create trigger trg_variant_cache after insert or update or delete on public.product_variants
  for each row execute function public.refresh_product_cache();

create trigger trg_review_rating after insert or update or delete on public.reviews
  for each row execute function public.refresh_product_rating();

create trigger trg_order_status_insert after insert on public.orders
  for each row execute function public.log_order_status();
create trigger trg_order_status_update after update of status on public.orders
  for each row execute function public.log_order_status();
