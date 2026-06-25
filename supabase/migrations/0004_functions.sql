-- ============================================================================
-- 0004_functions.sql — Fonctions utilitaires et fonctions de trigger
--
-- Dépendances : 0002 (tables). is_admin() est en LANGUAGE SQL : son corps est
--   validé à la création → public.profiles (0002) doit déjà exister.
-- Requis par : 0005 (triggers), 0006 (policies via is_admin), 0007 (RPC).
--
-- La RPC passer_commande() est volontairement isolée dans 0007_rpc.sql.
--
-- Sécurité : search_path = '' + schémas qualifiés ; SECURITY DEFINER là où la
-- fonction doit écrire dans des tables protégées par RLS.
-- ============================================================================

-- Admin = role 'admin' OU est_admin = true
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and (role = 'admin' or est_admin = true)
  );
$$;

-- updated_at automatique
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;

-- Création automatique du profil à l'inscription
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, new.raw_user_meta_data->>'full_name', new.phone)
  on conflict (id) do nothing;
  return new;
end; $$;

-- Empêche toute élévation de privilège : seul un admin peut fixer role/est_admin
create or replace function public.guard_profile_role()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then
      new.role := 'client';
      new.est_admin := false;
    else
      new.role := old.role;
      new.est_admin := old.est_admin;
    end if;
  end if;
  return new;
end; $$;

-- Application d'un mouvement de stock → met à jour stock_actuel (DEFINER : bypass RLS)
create or replace function public.apply_stock_movement()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.product_variants
     set stock_actuel = stock_actuel + new.quantity,
         updated_at   = now()
   where id = new.variant_id;
  return new;
end; $$;

-- Rafraîchit les caches prix_base / stock_total du produit (DEFINER : bypass RLS)
create or replace function public.refresh_product_cache()
returns trigger language plpgsql security definer set search_path = '' as $$
declare pid uuid;
begin
  pid := coalesce(new.product_id, old.product_id);
  update public.products p set
    prix_base = coalesce((select min(price) from public.product_variants v
                          where v.product_id = pid and v.is_active), 0),
    stock_total = coalesce((select sum(stock_actuel) from public.product_variants v
                            where v.product_id = pid), 0),
    updated_at = now()
  where p.id = pid;
  return null;
end; $$;

-- Rafraîchit les caches d'avis. DEFINER indispensable : un client (sans droit
-- d'UPDATE sur products) insère un avis → ce trigger doit pouvoir écrire le cache.
create or replace function public.refresh_product_rating()
returns trigger language plpgsql security definer set search_path = '' as $$
declare pid uuid;
begin
  pid := coalesce(new.product_id, old.product_id);
  update public.products p set
    rating_avg   = coalesce((select round(avg(rating)::numeric, 1) from public.reviews r
                             where r.product_id = pid and r.is_approved), 0),
    rating_count = coalesce((select count(*) from public.reviews r
                             where r.product_id = pid and r.is_approved), 0)
  where p.id = pid;
  return null;
end; $$;

-- Journalise tout changement de statut d'une commande (DEFINER : bypass RLS)
create or replace function public.log_order_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history (order_id, old_status, new_status, changed_by)
    values (new.id, null, new.status, auth.uid());
  elsif new.status is distinct from old.status then
    insert into public.order_status_history (order_id, old_status, new_status, changed_by)
    values (new.id, old.status, new.status, auth.uid());
  end if;
  return new;
end; $$;
