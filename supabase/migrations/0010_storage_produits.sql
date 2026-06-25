-- ============================================================================
-- 0010_storage_produits.sql — Bucket de stockage des photos produits
--
-- Active l'upload de fichiers (Supabase Storage) pour les images produits,
-- en remplacement du collage d'URL. Le bucket est public en lecture (la
-- boutique affiche les photos via leur URL publique) ; l'écriture est
-- réservée aux administrateurs via public.is_admin().
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('produits', 'produits', true)
on conflict (id) do nothing;

-- Lecture publique des objets du bucket
drop policy if exists "produits_read" on storage.objects;
create policy "produits_read" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'produits');

-- Écriture (insert/update/delete) réservée aux admins
drop policy if exists "produits_admin_insert" on storage.objects;
create policy "produits_admin_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'produits' and public.is_admin());

drop policy if exists "produits_admin_update" on storage.objects;
create policy "produits_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'produits' and public.is_admin())
  with check (bucket_id = 'produits' and public.is_admin());

drop policy if exists "produits_admin_delete" on storage.objects;
create policy "produits_admin_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'produits' and public.is_admin());
