-- Déclencheurs -> Edge Function notify via pg_net. La clé publishable envoyée
-- dans l'en-tête est PUBLIQUE (déjà dans le front) ; la clé REST OneSignal reste
-- côté serveur (secret d'Edge Function). notify re-lit la vérité en base.
create extension if not exists pg_net;

create or replace function public.notify_hook(p_payload jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := 'https://uxvalsjtnuhbauerylro.supabase.co/functions/v1/notify',
    body := p_payload,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'sb_publishable_fSoIxKIDRGtWHw-u7h2H4g_gIeaO5Yk'
    )
  );
exception when others then null; -- ne jamais bloquer la transaction métier
end; $$;
revoke execute on function public.notify_hook(jsonb) from public, anon, authenticated;

-- Nouvelle commande
create or replace function public.tg_order_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify_hook(jsonb_build_object('type', 'new_order', 'order_id', NEW.id));
  return NEW;
end; $$;
drop trigger if exists trg_notify_order_insert on public.orders;
create trigger trg_notify_order_insert after insert on public.orders
  for each row execute function public.tg_order_insert();

-- Changement de statut
create or replace function public.tg_order_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if NEW.status is distinct from OLD.status then
    perform public.notify_hook(jsonb_build_object('type', 'status_change', 'order_id', NEW.id, 'new_status', NEW.status::text));
  end if;
  return NEW;
end; $$;
drop trigger if exists trg_notify_order_status on public.orders;
create trigger trg_notify_order_status after update on public.orders
  for each row execute function public.tg_order_status();

-- Stock faible / rupture (au franchissement du seuil uniquement)
create or replace function public.tg_variant_stock()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (OLD.stock_actuel > 3 and NEW.stock_actuel <= 3)
     or (OLD.stock_actuel > 0 and NEW.stock_actuel <= 0) then
    perform public.notify_hook(jsonb_build_object('type', 'low_stock', 'variant_id', NEW.id));
  end if;
  return NEW;
end; $$;
drop trigger if exists trg_notify_variant_stock on public.product_variants;
create trigger trg_notify_variant_stock after update of stock_actuel on public.product_variants
  for each row execute function public.tg_variant_stock();

-- Nouvel avis à modérer
create or replace function public.tg_review_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(NEW.is_approved, false) = false then
    perform public.notify_hook(jsonb_build_object('type', 'new_review', 'review_id', NEW.id));
  end if;
  return NEW;
end; $$;
drop trigger if exists trg_notify_review_insert on public.reviews;
create trigger trg_notify_review_insert after insert on public.reviews
  for each row execute function public.tg_review_insert();
