-- ============================================================================
-- 0015_login_bruteforce_protection.sql
-- Verrou anti-brute-force sur la connexion client (mot de passe = PIN 6 chiffres).
-- Après 5 échecs, le compte est bloqué 15 minutes.
-- NB : voir 0016 pour le correctif de contrat (RETURN au lieu de RAISE).
-- ============================================================================

alter table public.comptes_clients
  add column if not exists failed_attempts int not null default 0,
  add column if not exists locked_until timestamptz;
