-- Audit : retrait de la fonction morte admin_login_email (remplacée par
-- admin_account_kind) qui exposait aussi un email admin à anon.
drop function if exists public.admin_login_email(text);

-- Défense en profondeur : les fonctions de gestion des accès sont déjà gardées
-- par is_owner(), mais on retire l'exécution par anon (grant PUBLIC par défaut).
revoke execute on function public.admin_member_add(text, text) from public, anon;
revoke execute on function public.admin_member_list() from public, anon;
revoke execute on function public.admin_member_remove(text) from public, anon;
