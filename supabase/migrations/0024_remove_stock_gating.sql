-- Plus de gestion de stock : les commandes ne sont plus bloquées ni décrémentées,
-- et l'alerte de stock faible est supprimée. Tout le monde commande librement.

-- 1) Supprime le trigger d'alerte de stock faible (plus de notification "stock").
drop trigger if exists trg_notify_variant_stock on public.product_variants;

-- 2) passer_commande sans vérification ni décrément de stock.
create or replace function public.passer_commande(p_customer_name text, p_customer_phone text, p_customer_address text, p_items jsonb, p_delivery_zone_id bigint DEFAULT NULL::bigint, p_coupon_code text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_channel text DEFAULT 'web'::text)
 RETURNS public.orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order       public.orders;
  v_variant     public.product_variants;
  v_coupon      public.coupons;
  v_zone        public.delivery_zones;
  v_line        record;
  v_qty         integer;
  v_subtotal    integer := 0;
  v_discount    integer := 0;
  v_delivery    integer := 0;
  v_free_thresh integer;
  v_total       integer;
  v_recent      integer;
  v_ref         text;
  v_uid         uuid := auth.uid();
begin
  if coalesce(trim(p_customer_name), '') = '' then
    raise exception 'Le nom du client est obligatoire.';
  end if;
  if coalesce(trim(p_customer_phone), '') = '' then
    raise exception 'Le numéro de téléphone est obligatoire.';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Le panier est vide.';
  end if;
  if jsonb_array_length(p_items) > 50 then
    raise exception 'Trop d''articles dans la commande.';
  end if;

  select count(*) into v_recent
  from public.orders
  where customer_phone = trim(p_customer_phone)
    and created_at > now() - interval '10 minutes';
  if v_recent >= 5 then
    raise exception 'Trop de commandes en peu de temps. Réessayez plus tard.';
  end if;

  select free_delivery_threshold into v_free_thresh from public.settings where id = 1;
  if p_delivery_zone_id is not null then
    select * into v_zone from public.delivery_zones where id = p_delivery_zone_id;
    if not found or not v_zone.is_active then
      raise exception 'Zone de livraison invalide.';
    end if;
    v_delivery := v_zone.fee;
  else
    select coalesce(delivery_fee, 0) into v_delivery from public.settings where id = 1;
  end if;

  v_ref := 'PSN-' || to_char(now(), 'YYYY') || '-'
           || lpad(nextval('public.order_ref_seq')::text, 6, '0');

  insert into public.orders (reference, user_id, customer_name, customer_phone,
                             customer_address, status, subtotal, discount,
                             delivery_fee, total, delivery_zone_id, channel, note)
  values (v_ref, v_uid, trim(p_customer_name), trim(p_customer_phone),
          nullif(trim(coalesce(p_customer_address, '')), ''), 'en_attente',
          0, 0, v_delivery, 0, p_delivery_zone_id, coalesce(p_channel, 'web'), p_note)
  returning * into v_order;

  for v_line in
    select (e->>'variant_id')::uuid as vid,
           sum((e->>'quantity')::int) as qty
    from jsonb_array_elements(p_items) as e
    group by 1
    order by 1
  loop
    v_qty := v_line.qty;
    if v_line.vid is null then raise exception 'Article invalide.'; end if;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantité invalide.'; end if;
    if v_qty > 20 then raise exception 'Quantité par article trop élevée (max 20).'; end if;

    select * into v_variant
    from public.product_variants
    where id = v_line.vid;

    if not found or not v_variant.is_active then
      raise exception 'Produit indisponible.';
    end if;
    -- (Plus de vérification de stock : commande libre.)

    insert into public.order_items (order_id, variant_id, product_id, product_name,
                                    variant_label, brand, unit_price, quantity, line_total)
    select v_order.id, v_variant.id, v_variant.product_id, p.name,
           v_variant.label, p.brand, v_variant.price, v_qty, v_variant.price * v_qty
    from public.products p where p.id = v_variant.product_id;

    -- (Plus de mouvement de stock : le stock n'est plus décrémenté.)

    v_subtotal := v_subtotal + v_variant.price * v_qty;
  end loop;

  if p_coupon_code is not null and trim(p_coupon_code) <> '' then
    select * into v_coupon from public.coupons
    where code = upper(trim(p_coupon_code)) for update;

    if not found or not v_coupon.is_active then
      raise exception 'Code promo invalide.';
    end if;
    if v_coupon.starts_at is not null and now() < v_coupon.starts_at then
      raise exception 'Code promo pas encore actif.';
    end if;
    if v_coupon.ends_at is not null and now() > v_coupon.ends_at then
      raise exception 'Code promo expiré.';
    end if;
    if v_subtotal < v_coupon.min_order then
      raise exception 'Montant minimum non atteint pour ce code.';
    end if;
    if v_coupon.usage_limit is not null and v_coupon.used_count >= v_coupon.usage_limit then
      raise exception 'Code promo épuisé.';
    end if;
    if v_coupon.usage_limit_per_user is not null and v_uid is not null
       and (select count(*) from public.coupon_redemptions r
            where r.coupon_id = v_coupon.id and r.user_id = v_uid)
           >= v_coupon.usage_limit_per_user then
      raise exception 'Vous avez déjà utilisé ce code.';
    end if;

    if v_coupon.discount_type = 'percent' then
      v_discount := floor(v_subtotal * v_coupon.discount_value / 100.0);
    else
      v_discount := v_coupon.discount_value;
    end if;
    if v_coupon.max_discount is not null then
      v_discount := least(v_discount, v_coupon.max_discount);
    end if;
    v_discount := least(v_discount, v_subtotal);

    insert into public.coupon_redemptions (coupon_id, order_id, user_id, amount)
    values (v_coupon.id, v_order.id, v_uid, v_discount);
    update public.coupons set used_count = used_count + 1 where id = v_coupon.id;
  end if;

  if v_free_thresh is not null and (v_subtotal - v_discount) >= v_free_thresh then
    v_delivery := 0;
  end if;

  v_total := v_subtotal - v_discount + v_delivery;

  update public.orders set
    subtotal     = v_subtotal,
    discount     = v_discount,
    delivery_fee = v_delivery,
    total        = v_total,
    coupon_id    = v_coupon.id
  where id = v_order.id
  returning * into v_order;

  return v_order;
end; $function$;
