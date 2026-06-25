-- ============================================================================
-- 0002_tables.sql — Tables (16)
--
-- Dépendances : 0001 (types ENUM : order_status, stock_movement_type, discount_type).
-- Les tables sont créées dans l'ordre des clés étrangères (référencé avant référent).
-- Requis par : 0003, 0004, 0005, 0006, 0007, 0008.
-- ============================================================================

-- ---- 1. settings (singleton) ----------------------------------------------
create table public.settings (
  id            smallint primary key default 1 check (id = 1),
  store_name    text not null default 'portable.sn',
  logo_url      text,
  whatsapp_number text,
  currency      text not null default 'FCFA',
  delivery_fee  integer not null default 0 check (delivery_fee >= 0),
  free_delivery_threshold integer check (free_delivery_threshold >= 0),
  color_primary text default '#2563eb',
  color_accent  text default '#16a34a',
  contact_email text,
  contact_address text,
  is_open       boolean not null default true,
  extra         jsonb not null default '{}',
  updated_at    timestamptz not null default now()
);

-- ---- 2. banners (slider d'accueil) ----------------------------------------
create table public.banners (
  id         bigint generated always as identity primary key,
  title      text,
  subtitle   text,
  image_url  text not null,
  link_url   text,
  position   int not null default 0,
  is_active  boolean not null default true,
  starts_at  timestamptz,
  ends_at    timestamptz,
  created_at timestamptz not null default now(),
  constraint banner_dates check (ends_at is null or starts_at is null or ends_at > starts_at)
);

-- ---- 3. categories (avec sous-catégories) ---------------------------------
create table public.categories (
  id         bigint generated always as identity primary key,
  slug       text not null unique,
  name       text not null,
  parent_id  bigint references public.categories(id) on delete set null,
  position   int not null default 0,
  image_url  text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---- 4. products (conteneur + caches) -------------------------------------
create table public.products (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique,
  name         text not null,
  brand        text,
  category_id  bigint references public.categories(id) on delete set null,
  description  text,
  image_url    text,                         -- couverture (cache)
  is_hot       boolean not null default false,
  is_active    boolean not null default true,
  prix_base    integer not null default 0,   -- cache = min(price) des variantes actives
  stock_total  integer not null default 0,   -- cache = somme(stock_actuel) des variantes
  rating_avg   numeric(2,1) not null default 0,
  rating_count integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---- 5. product_variants (SKU vendable) -----------------------------------
create table public.product_variants (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references public.products(id) on delete cascade,
  sku           text unique,
  label         text not null,
  color         text,
  storage       text,
  attributes    jsonb not null default '{}',
  price         integer not null check (price >= 0),
  old_price     integer check (old_price >= 0),
  stock_initial integer not null default 0 check (stock_initial >= 0),
  stock_actuel  integer not null default 0 check (stock_actuel >= 0),
  is_active     boolean not null default true,
  position      int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint promo_valide check (old_price is null or old_price > price)
);

-- ---- 6. product_images (galerie) ------------------------------------------
create table public.product_images (
  id         bigint generated always as identity primary key,
  product_id uuid not null references public.products(id) on delete cascade,
  variant_id uuid references public.product_variants(id) on delete cascade,
  url        text not null,
  alt        text,
  position   int not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---- 7. profiles (comptes) ------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  address    text,
  role       text not null default 'client',
  est_admin  boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---- 8. favorites ---------------------------------------------------------
create table public.favorites (
  user_id    uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

-- ---- 9. coupons -----------------------------------------------------------
create table public.coupons (
  id             bigint generated always as identity primary key,
  code           text not null unique,
  description    text,
  discount_type  public.discount_type not null,
  discount_value integer not null check (discount_value > 0),
  min_order      integer not null default 0 check (min_order >= 0),
  max_discount   integer check (max_discount >= 0),
  starts_at      timestamptz,
  ends_at        timestamptz,
  usage_limit          integer check (usage_limit >= 0),
  usage_limit_per_user integer check (usage_limit_per_user >= 0),
  used_count     integer not null default 0 check (used_count >= 0),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  -- code stocké en MAJUSCULES : la RPC fait la recherche via upper(code)
  constraint code_majuscules check (code = upper(code)),
  constraint percent_range  check (discount_type <> 'percent' or discount_value between 1 and 100),
  constraint dates_valides  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

-- ---- 9b. delivery_zones (zones de livraison par région) -------------------
create table public.delivery_zones (
  id         bigint generated always as identity primary key,
  name       text not null unique,
  fee        integer not null default 0 check (fee >= 0),  -- frais de livraison (FCFA)
  position   int not null default 0,                       -- ordre d'affichage
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---- 10. orders -----------------------------------------------------------
create table public.orders (
  id               uuid primary key default gen_random_uuid(),
  reference        text not null unique,
  user_id          uuid references auth.users(id) on delete set null,  -- null = invité
  customer_name    text not null,
  customer_phone   text not null,
  customer_address text,
  status           public.order_status not null default 'en_attente',
  subtotal         integer not null default 0 check (subtotal >= 0),
  discount         integer not null default 0 check (discount >= 0),
  delivery_fee     integer not null default 0 check (delivery_fee >= 0),
  total            integer not null default 0 check (total >= 0),
  currency         text not null default 'FCFA',
  coupon_id        bigint references public.coupons(id) on delete set null,
  delivery_zone_id bigint references public.delivery_zones(id) on delete set null,
  channel          text not null default 'web',     -- 'web' | 'whatsapp'
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ---- 11. stock_movements (journal) ----------------------------------------
create table public.stock_movements (
  id         bigint generated always as identity primary key,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  type       public.stock_movement_type not null,
  quantity   integer not null,        -- + entrée / - sortie
  reason     text,
  order_id   uuid references public.orders(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ---- 12. coupon_redemptions -----------------------------------------------
create table public.coupon_redemptions (
  id         bigint generated always as identity primary key,
  coupon_id  bigint not null references public.coupons(id) on delete cascade,
  order_id   uuid not null references public.orders(id) on delete cascade,
  user_id    uuid references auth.users(id) on delete set null,
  amount     integer not null check (amount >= 0),
  created_at timestamptz not null default now()
);

-- ---- 13. order_items (lignes, snapshots) ----------------------------------
create table public.order_items (
  id            bigint generated always as identity primary key,
  order_id      uuid not null references public.orders(id) on delete cascade,
  variant_id    uuid references public.product_variants(id) on delete set null,
  product_id    uuid references public.products(id) on delete set null,
  product_name  text not null,
  variant_label text,
  brand         text,
  unit_price    integer not null check (unit_price >= 0),
  quantity      integer not null check (quantity > 0),
  line_total    integer not null check (line_total >= 0)
);

-- ---- 14. reviews (avis clients) -------------------------------------------
create table public.reviews (
  id          bigint generated always as identity primary key,
  product_id  uuid not null references public.products(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete set null,
  order_id    uuid references public.orders(id) on delete set null,  -- achat vérifié
  author_name text,
  rating      smallint not null check (rating between 1 and 5),
  comment     text,
  is_approved boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (product_id, user_id)
);

-- ---- 15. order_status_history (traçabilité des statuts) -------------------
create table public.order_status_history (
  id         bigint generated always as identity primary key,
  order_id   uuid not null references public.orders(id) on delete cascade,
  old_status public.order_status,
  new_status public.order_status not null,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
