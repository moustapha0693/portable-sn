-- ============================================================================
-- 0012_inscription_client.sql — Inscription client par numéro + code (PIN)
--
-- Crée un compte Supabase Auth sans SMS ni e-mail de confirmation :
--   * le numéro (+221 + 9 chiffres) est transformé en e-mail interne
--     "221XXXXXXXXX@portable.sn" (jamais envoyé, sert d'identifiant) ;
--   * le code à 6 chiffres devient le mot de passe (haché bcrypt par Supabase).
-- Le client se connecte ensuite via signInWithPassword(email, pin) — donc le
-- même code fonctionne sur tous les navigateurs/appareils.
-- ============================================================================
create or replace function public.inscription_client(p_phone text, p_pin text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_email  text;
  v_uid    uuid := gen_random_uuid();
begin
  if length(v_digits) <> 9 then raise exception 'Numéro invalide (9 chiffres).'; end if;
  if p_pin !~ '^\d{6}$'   then raise exception 'Le code doit comporter 6 chiffres.'; end if;

  v_email := '221' || v_digits || '@portable.sn';
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Ce numéro a déjà un compte. Connecte-toi avec ton code.';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_pin, extensions.gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', '', ''
  );

  insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
  values (v_uid::text, v_uid,
          jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true),
          'email', now(), now());

  -- Le trigger handle_new_user a créé le profil ; on y renseigne le téléphone.
  update public.profiles set phone = '221' || v_digits where id = v_uid;
end; $$;

grant execute on function public.inscription_client(text, text) to anon, authenticated;
