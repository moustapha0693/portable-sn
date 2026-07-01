-- ============================================================================
-- 0016_login_bruteforce_fix.sql
-- connexion_client : un RAISE annule toutes les écritures de la fonction, donc
-- l'incrément du compteur d'échecs (0015) était systématiquement perdu. On
-- renvoie désormais un objet {ok:false, error:...} (un RETURN conserve les
-- UPDATE) au lieu de lever une exception. Le front lit data.ok / data.error.
-- ============================================================================

create or replace function public.connexion_client(p_phone text, p_pin text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.comptes_clients; v_token text; v_new int;
begin
  select * into v from public.comptes_clients where phone = p_phone;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Numéro ou mot de passe incorrect.');
  end if;
  if v.locked_until is not null and v.locked_until > now() then
    return jsonb_build_object('ok', false, 'error', 'Trop de tentatives. Réessaie dans quelques minutes.');
  end if;
  if v.pin_hash <> extensions.crypt(p_pin, v.pin_hash) then
    v_new := v.failed_attempts + 1;
    if v_new >= 5 then
      update public.comptes_clients set failed_attempts = 0, locked_until = now() + interval '15 minutes' where id = v.id;
      return jsonb_build_object('ok', false, 'error', 'Trop de tentatives. Compte bloqué 15 minutes.');
    else
      update public.comptes_clients set failed_attempts = v_new where id = v.id;
      return jsonb_build_object('ok', false, 'error', 'Numéro ou mot de passe incorrect.');
    end if;
  end if;
  -- succès
  v_token := gen_random_uuid()::text;
  update public.comptes_clients
     set session_token = v_token, failed_attempts = 0, locked_until = null
   where id = v.id;
  return jsonb_build_object('ok', true, 'phone', v.phone, 'full_name', v.full_name,
    'region', v.region, 'quartier', v.quartier, 'token', v_token);
end; $$;
