-- ============================================================================
-- 0021 : Centre de notifications interne (sans push web). Les événements métier
-- écrivent des lignes dans public.notifications (source de vérité). Le web les
-- lit ; plus tard, un push mobile pourra être ajouté (ex. trigger AFTER INSERT
-- sur notifications) SANS toucher à la logique métier ci-dessous.
-- ============================================================================

create table if not exists public.notifications (
  id         bigint generated always as identity primary key,
  phone      text,                              -- destinataire client (9 chiffres), null si admin
  audience   text not null default 'client',    -- 'client' | 'admin'
  user_id    uuid,                              -- réservé (auth) pour évolution
  title      text not null,
  message    text not null,
  type       text not null default 'info',      -- order_new, order_status, low_stock, review, promo, message, info
  is_read    boolean not null default false,
  data       jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_notifications_phone on public.notifications (phone, created_at desc);
create index if not exists idx_notifications_audience on public.notifications (audience, created_at desc);
alter table public.notifications enable row level security; -- deny-all : accès via RPC uniquement

-- Format monétaire lisible, indépendant de la locale : 102000 -> "102 000 FCFA".
create or replace function public.format_fcfa(n numeric)
returns text language sql immutable set search_path = '' as $$
  select reverse(regexp_replace(reverse((round(coalesce(n,0)))::bigint::text), '(\d{3})(?=\d)', '\1 ', 'g')) || ' FCFA';
$$;

-- Helper interne : crée une notification (utilisé par les triggers). Non exposé.
create or replace function public.notifier(
  p_phone text, p_audience text, p_title text, p_message text, p_type text, p_data jsonb default null
) returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into public.notifications(phone, audience, title, message, type, data)
  values (nullif(right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9), ''),
          coalesce(nullif(p_audience,''), 'client'), p_title, p_message, coalesce(nullif(p_type,''), 'info'), p_data)
  returning id into v_id;
  return v_id;
end; $$;
revoke execute on function public.notifier(text, text, text, text, text, jsonb) from public, anon, authenticated;

-- ---- API client (boîte de réception), par jeton de session ------------------
create or replace function public.mes_notifications(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_phone text;
begin
  if coalesce(p_token,'') = '' then return '[]'::jsonb; end if;
  select right(regexp_replace(phone, '\D', '', 'g'), 9) into v_phone
    from public.comptes_clients where session_token = p_token;
  if v_phone is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', n.id, 'title', n.title, 'message', n.message,
             'type', n.type, 'is_read', n.is_read, 'data', n.data, 'created_at', n.created_at)
           order by n.created_at desc)
    from public.notifications n where n.phone = v_phone and n.audience = 'client'
  ), '[]'::jsonb);
end; $$;
grant execute on function public.mes_notifications(text) to anon, authenticated;

create or replace function public.notifications_non_lues(p_token text)
returns integer language plpgsql stable security definer set search_path = '' as $$
declare v_phone text; v int;
begin
  if coalesce(p_token,'') = '' then return 0; end if;
  select right(regexp_replace(phone, '\D', '', 'g'), 9) into v_phone
    from public.comptes_clients where session_token = p_token;
  if v_phone is null then return 0; end if;
  select count(*) into v from public.notifications where phone = v_phone and audience = 'client' and is_read = false;
  return coalesce(v, 0);
end; $$;
grant execute on function public.notifications_non_lues(text) to anon, authenticated;

create or replace function public.notifications_marquer_lues(p_token text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_phone text; v int;
begin
  if coalesce(p_token,'') = '' then return 0; end if;
  select right(regexp_replace(phone, '\D', '', 'g'), 9) into v_phone
    from public.comptes_clients where session_token = p_token;
  if v_phone is null then return 0; end if;
  update public.notifications set is_read = true
    where phone = v_phone and audience = 'client' and is_read = false;
  get diagnostics v = row_count; return v;
end; $$;
grant execute on function public.notifications_marquer_lues(text) to anon, authenticated;

create or replace function public.notification_supprimer(p_token text, p_id bigint)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_phone text; v int;
begin
  if coalesce(p_token,'') = '' then return false; end if;
  select right(regexp_replace(phone, '\D', '', 'g'), 9) into v_phone
    from public.comptes_clients where session_token = p_token;
  if v_phone is null then return false; end if;
  delete from public.notifications where id = p_id and phone = v_phone and audience = 'client';
  get diagnostics v = row_count; return v > 0;
end; $$;
grant execute on function public.notification_supprimer(text, bigint) to anon, authenticated;

-- Diffusion promo : le propriétaire crée une notif pour chaque client.
create or replace function public.diffuser_promo(p_title text, p_message text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  if not public.is_owner() then raise exception 'Réservé au propriétaire.'; end if;
  if coalesce(trim(p_message),'') = '' then raise exception 'Message vide.'; end if;
  insert into public.notifications(phone, audience, title, message, type)
  select right(regexp_replace(c.phone, '\D', '', 'g'), 9), 'client',
         coalesce(nullif(trim(p_title),''), 'portable.sn'), p_message, 'promo'
  from public.comptes_clients c;
  get diagnostics v = row_count; return v;
end; $$;
grant execute on function public.diffuser_promo(text, text) to authenticated;
revoke execute on function public.diffuser_promo(text, text) from anon, public;

-- ---- Les triggers métier écrivent désormais dans notifications --------------
create or replace function public.tg_order_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if NEW.customer_phone is not null then
    perform public.notifier(NEW.customer_phone, 'client', 'Commande reçue',
      'Ta commande ' || NEW.reference || ' est bien reçue. Total ' || public.format_fcfa(NEW.total) || '.',
      'order_status', jsonb_build_object('order_id', NEW.id, 'reference', NEW.reference));
  end if;
  perform public.notifier(null, 'admin', 'Nouvelle commande',
    NEW.reference || ' — ' || NEW.customer_name || ' — ' || public.format_fcfa(NEW.total),
    'order_new', jsonb_build_object('order_id', NEW.id, 'reference', NEW.reference));
  return NEW;
end; $$;

create or replace function public.tg_order_status()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_title text; v_msg text;
begin
  if NEW.status is distinct from OLD.status and NEW.customer_phone is not null then
    case NEW.status::text
      when 'confirmee'    then v_title := 'Commande confirmée';  v_msg := 'Ta commande ' || NEW.reference || ' est confirmée.';
      when 'en_livraison' then v_title := 'En livraison';        v_msg := 'Ta commande ' || NEW.reference || ' est en cours de livraison.';
      when 'livree'       then v_title := 'Commande livrée';     v_msg := 'Ta commande ' || NEW.reference || ' est livrée. Merci !';
      when 'annulee'      then v_title := 'Commande annulée';    v_msg := 'Ta commande ' || NEW.reference || ' a été annulée.';
      else v_title := null;
    end case;
    if v_title is not null then
      perform public.notifier(NEW.customer_phone, 'client', v_title, v_msg, 'order_status',
        jsonb_build_object('order_id', NEW.id, 'reference', NEW.reference, 'status', NEW.status::text));
    end if;
  end if;
  return NEW;
end; $$;

create or replace function public.tg_variant_stock()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text; v_lbl text; v_msg text;
begin
  if (OLD.stock_actuel > 3 and NEW.stock_actuel <= 3)
     or (OLD.stock_actuel > 0 and NEW.stock_actuel <= 0) then
    select name into v_name from public.products where id = NEW.product_id;
    v_lbl := case when NEW.label is not null and NEW.label <> 'Standard' then ' (' || NEW.label || ')' else '' end;
    v_msg := case when NEW.stock_actuel <= 0 then 'Rupture de stock : ' || coalesce(v_name, 'Produit') || v_lbl
                  else 'Stock faible : ' || coalesce(v_name, 'Produit') || v_lbl || ' — ' || NEW.stock_actuel || ' restant(s)' end;
    perform public.notifier(null, 'admin', 'Alerte stock', v_msg, 'low_stock', jsonb_build_object('variant_id', NEW.id));
  end if;
  return NEW;
end; $$;

create or replace function public.tg_review_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text;
begin
  if coalesce(NEW.is_approved, false) = false then
    select name into v_name from public.products where id = NEW.product_id;
    perform public.notifier(null, 'admin', 'Nouvel avis',
      coalesce(NEW.rating::text, '?') || '★ sur ' || coalesce(v_name, 'un produit') || ' — à modérer',
      'review', jsonb_build_object('review_id', NEW.id));
  end if;
  return NEW;
end; $$;
