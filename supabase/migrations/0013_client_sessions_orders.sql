-- ============================================================================
-- 0013_client_sessions_orders.sql
--
-- Ajoute un jeton de session aux comptes clients (auth téléphone + mot de passe)
-- et une RPC sécurisée pour qu'un client consulte SES commandes (statut,
-- détails, historique) sans exposer celles des autres.
-- ============================================================================

alter table public.comptes_clients add column if not exists session_token text;
create index if not exists idx_comptes_clients_token on public.comptes_clients(session_token);

-- Inscription : crée le compte + un jeton de session, renvoyé au client.
create or replace function public.inscription_client(
  p_phone text, p_pin text, p_full_name text, p_region text, p_quartier text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients; v_token text;
begin
  if p_phone !~ '^[0-9]{9}$' then raise exception 'Numéro invalide (9 chiffres).'; end if;
  if p_pin !~ '^[0-9]{6}$' then raise exception 'Le mot de passe doit comporter 6 chiffres.'; end if;
  if exists (select 1 from public.comptes_clients where phone = p_phone) then
    raise exception 'Un compte existe déjà avec ce numéro.';
  end if;
  v_token := gen_random_uuid()::text;
  insert into public.comptes_clients (phone, pin_hash, full_name, region, quartier, session_token)
  values (p_phone, extensions.crypt(p_pin, extensions.gen_salt('bf')),
          nullif(trim(p_full_name), ''), nullif(trim(p_region), ''), nullif(trim(p_quartier), ''), v_token)
  returning * into v;
  return jsonb_build_object('phone', v.phone, 'full_name', v.full_name,
    'region', v.region, 'quartier', v.quartier, 'token', v_token);
end; $$;

-- Connexion : vérifie le mot de passe, fait tourner un nouveau jeton, le renvoie.
create or replace function public.connexion_client(p_phone text, p_pin text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients; v_token text;
begin
  select * into v from public.comptes_clients where phone = p_phone;
  if not found or v.pin_hash <> extensions.crypt(p_pin, v.pin_hash) then
    raise exception 'Numéro ou mot de passe incorrect.';
  end if;
  v_token := gen_random_uuid()::text;
  update public.comptes_clients set session_token = v_token where id = v.id;
  return jsonb_build_object('phone', v.phone, 'full_name', v.full_name,
    'region', v.region, 'quartier', v.quartier, 'token', v_token);
end; $$;

-- Mes commandes : renvoie les commandes du client (identifié par son jeton),
-- avec articles et historique de statut. Rapprochement par téléphone (9 chiffres).
create or replace function public.mes_commandes(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients; result jsonb;
begin
  if p_token is null or p_token = '' then raise exception 'Non connecté.'; end if;
  select * into v from public.comptes_clients where session_token = p_token;
  if not found then raise exception 'Session expirée, reconnecte-toi.'; end if;

  select coalesce(jsonb_agg(obj order by created_at desc), '[]'::jsonb) into result
  from (
    select o.created_at, jsonb_build_object(
      'id', o.id, 'reference', o.reference, 'status', o.status, 'created_at', o.created_at,
      'subtotal', o.subtotal, 'discount', o.discount, 'delivery_fee', o.delivery_fee, 'total', o.total,
      'customer_address', o.customer_address,
      'zone', (select z.name from public.delivery_zones z where z.id = o.delivery_zone_id),
      'items', (select coalesce(jsonb_agg(jsonb_build_object(
                  'product_name', i.product_name, 'variant_label', i.variant_label,
                  'unit_price', i.unit_price, 'quantity', i.quantity, 'line_total', i.line_total) order by i.id), '[]'::jsonb)
                from public.order_items i where i.order_id = o.id),
      'history', (select coalesce(jsonb_agg(jsonb_build_object(
                    'old_status', h.old_status, 'new_status', h.new_status, 'created_at', h.created_at) order by h.created_at), '[]'::jsonb)
                  from public.order_status_history h where h.order_id = o.id)
    ) as obj
    from public.orders o
    where right(regexp_replace(o.customer_phone, '[^0-9]', '', 'g'), 9) = v.phone
  ) t;
  return result;
end; $$;

grant execute on function public.inscription_client(text,text,text,text,text) to anon, authenticated;
grant execute on function public.connexion_client(text,text) to anon, authenticated;
grant execute on function public.mes_commandes(text) to anon, authenticated;
