// assistant-login : pont "compte boutique -> session admin".
// L'assistant se connecte avec son numéro + mot de passe boutique (PIN). Cette
// fonction (service_role) vérifie via assistant_verify (num + PIN + appartenance
// + verrou anti-brute-force), crée au besoin un compte Supabase synthétique
// (mot de passe aléatoire jamais utilisé), lui accorde est_admin, puis renvoie un
// token_hash de lien magique que le client échange en session (verifyOtp).
// verify_jwt = false : la protection est le PIN + l'appartenance (clé publishable
// non-JWT du projet). Aucun secret n'est exposé côté client.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'Méthode non autorisée.' }, 405);

  let phone = '', pin = '';
  try {
    const body = await req.json();
    phone = String(body.phone ?? '');
    pin = String(body.pin ?? '');
  } catch (_) {
    return json({ ok: false, error: 'Requête invalide.' }, 400);
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // 1) Vérifie numéro + PIN + appartenance (verrou anti-brute-force côté SQL).
  const { data: v, error: ve } = await admin.rpc('assistant_verify', { p_phone: phone, p_pin: pin });
  if (ve) return json({ ok: false, error: 'Erreur serveur.' }, 200);
  if (!v || v.ok !== true) return json({ ok: false, error: (v && v.error) || 'Accès refusé.' }, 200);

  // Propriétaire comme assistant : le pont ouvre la session du compte lié
  // (email réel pour le propriétaire = son compte is_owner ; synthétique sinon),
  // à partir du code boutique. Aucun mot de passe Supabase distinct à retenir.
  const email = String(v.email);

  // 2) Crée le compte synthétique si besoin (mot de passe aléatoire, jamais utilisé).
  const randomPw = crypto.randomUUID() + crypto.randomUUID();
  const created = await admin.auth.admin.createUser({
    email,
    password: randomPw,
    email_confirm: true,
    user_metadata: { assistant: true, phone: v.phone, full_name: v.full_name ?? null },
  });
  // Si déjà existant, createUser renvoie une erreur qu'on ignore.

  // 3) Accorde les droits admin au compte lié.
  await admin.rpc('admin_grant_by_email', { p_email: email });

  // 4) Génère un lien magique -> token_hash (session ouverte côté client).
  const { data: link, error: le } = await admin.auth.admin.generateLink({ type: 'magiclink', email });
  const tokenHash = link?.properties?.hashed_token;
  if (le || !tokenHash) return json({ ok: false, error: 'Connexion impossible. Réessaie.' }, 200);

  return json({ ok: true, token_hash: tokenHash, created: !created.error });
});
