-- Retire les stats de stock du tableau de bord (plus de gestion de stock).
create or replace function public.admin_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare res jsonb;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs.'; end if;
  select jsonb_build_object(
    'platform_users',  (select count(*) from public.comptes_clients),
    'orders_total',    (select count(*) from public.orders),
    'orders_today',    (select count(*) from public.orders where created_at >= date_trunc('day', now())),
    'orders_pending',  (select count(*) from public.orders where status = 'en_attente'),
    'orders_delivered',(select count(*) from public.orders where status = 'livree'),
    'products_active', (select count(*) from public.products where is_active),
    'reviews_pending', (select count(*) from public.reviews where is_approved = false),
    'by_status',       (select coalesce(jsonb_object_agg(status, c), '{}'::jsonb)
                          from (select status::text, count(*) c from public.orders group by status) s),
    'orders_14d',      (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'orders', o) order by d), '[]'::jsonb)
                          from (select gs::date d,
                                  (select count(*) from public.orders where created_at::date = gs::date) o
                                from generate_series(now()::date - interval '13 days', now()::date, interval '1 day') gs) x),
    'top_products',    (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'qty', qty) order by qty desc), '[]'::jsonb)
                          from (select product_name as name, sum(quantity) qty
                                from public.order_items group by product_name order by sum(quantity) desc limit 5) z),
    'recent_orders',   (select coalesce(jsonb_agg(jsonb_build_object('reference', reference, 'name', customer_name, 'status', status, 'created_at', created_at) order by created_at desc), '[]'::jsonb)
                          from (select reference, customer_name, status::text as status, created_at
                                from public.orders order by created_at desc limit 8) z)
  ) into res;
  return res;
end; $$;
grant execute on function public.admin_dashboard() to authenticated;
revoke execute on function public.admin_dashboard() from anon, public;
