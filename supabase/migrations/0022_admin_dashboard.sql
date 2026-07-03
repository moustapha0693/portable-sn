-- Tableau de bord admin : toutes les stats en un appel (SECURITY DEFINER,
-- réservé aux admins ; lit aussi comptes_clients qui est en deny-all RLS).
create or replace function public.admin_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare res jsonb;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs.'; end if;
  select jsonb_build_object(
    'revenue_total',   coalesce((select sum(total) from public.orders where status <> 'annulee'), 0),
    'revenue_month',   coalesce((select sum(total) from public.orders where status <> 'annulee' and created_at >= date_trunc('month', now())), 0),
    'orders_total',    (select count(*) from public.orders),
    'orders_today',    (select count(*) from public.orders where created_at >= date_trunc('day', now())),
    'orders_pending',  (select count(*) from public.orders where status = 'en_attente'),
    'products_active', (select count(*) from public.products where is_active),
    'clients',         (select count(*) from public.comptes_clients),
    'low_stock',       (select count(*) from public.product_variants where is_active and stock_actuel <= 3),
    'reviews_pending', (select count(*) from public.reviews where is_approved = false),
    'by_status',       (select coalesce(jsonb_object_agg(status, c), '{}'::jsonb)
                          from (select status::text, count(*) c from public.orders group by status) s),
    'sales_14d',       (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'orders', o, 'revenue', r) order by d), '[]'::jsonb)
                          from (select gs::date d,
                                  (select count(*) from public.orders where created_at::date = gs::date) o,
                                  (select coalesce(sum(total),0) from public.orders where created_at::date = gs::date and status <> 'annulee') r
                                from generate_series(now()::date - interval '13 days', now()::date, interval '1 day') gs) x),
    'top_products',    (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'qty', qty, 'revenue', rev) order by qty desc), '[]'::jsonb)
                          from (select product_name as name, sum(quantity) qty, sum(line_total) rev
                                from public.order_items group by product_name order by sum(quantity) desc limit 5) z),
    'low_stock_list',  (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'label', label, 'stock', stock) order by stock), '[]'::jsonb)
                          from (select pr.name, v.label, v.stock_actuel as stock
                                from public.product_variants v join public.products pr on pr.id = v.product_id
                                where v.is_active and v.stock_actuel <= 3 order by v.stock_actuel limit 12) z),
    'recent_orders',   (select coalesce(jsonb_agg(jsonb_build_object('reference', reference, 'name', customer_name, 'total', total, 'status', status, 'created_at', created_at) order by created_at desc), '[]'::jsonb)
                          from (select reference, customer_name, total, status::text as status, created_at
                                from public.orders order by created_at desc limit 8) z)
  ) into res;
  return res;
end; $$;
grant execute on function public.admin_dashboard() to authenticated;
revoke execute on function public.admin_dashboard() from anon, public;
