// notify : envoie les notifications push OneSignal (clé REST lue via Deno.env.get,
// jamais dans le dépôt). Appelée par des déclencheurs DB (nouvelle commande,
// changement de statut, stock faible, avis) via pg_net, et par l'admin pour la
// diffusion promo (authentifié propriétaire).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ONESIGNAL_API = 'https://onesignal.com/api/v1/notifications';
const SITE_URL = 'https://portable-sn.vercel.app';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
const norm = (p: unknown) => String(p ?? '').replace(/\D/g, '').slice(-9);
const fmt = (n: number) => new Intl.NumberFormat('fr-FR').format(n) + ' FCFA';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'Méthode non autorisée.' }, 405);

  const appId = Deno.env.get('ONESIGNAL_APP_ID');
  const restKey = Deno.env.get('ONESIGNAL_REST_API_KEY');
  if (!appId || !restKey) return json({ ok: false, error: 'OneSignal non configuré (secrets manquants).' }, 200);

  const supaUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(supaUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  let body: any;
  try { body = await req.json(); } catch (_) { return json({ ok: false, error: 'JSON invalide.' }, 400); }
  const type = String(body?.type ?? '');

  const ADMIN_FILTER = [{ field: 'tag', key: 'role', relation: '=', value: 'admin' }];

  async function osSend(payload: Record<string, unknown>) {
    const res = await fetch(ONESIGNAL_API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8', 'Authorization': `Basic ${restKey}` },
      body: JSON.stringify({ app_id: appId, ...payload }),
    });
    const data = await res.json().catch(() => ({}));
    console.log('osSend', res.status, JSON.stringify(data));
    return { status: res.status, data };
  }
  const toAdmins = (heading: string, content: string, url = SITE_URL + '/admin.html') =>
    osSend({ filters: ADMIN_FILTER, headings: { en: heading, fr: heading }, contents: { en: content, fr: content }, url });
  const toClient = (phone: string, heading: string, content: string) =>
    osSend({ include_external_user_ids: [norm(phone)], headings: { en: heading, fr: heading }, contents: { en: content, fr: content }, url: SITE_URL });

  try {
    if (type === 'selftest') {
      // Valide la clé REST sans spammer : cible un utilisateur externe inexistant.
      const r = await osSend({ include_external_user_ids: ['__selftest_nobody__'], headings: { en: 'selftest', fr: 'selftest' }, contents: { en: 'selftest', fr: 'selftest' } });
      const ok = r.status >= 200 && r.status < 300;
      return json({ ok, status: r.status, key_valid: r.status !== 401 && r.status !== 403, onesignal: r.data }, 200);
    }

    if (type === 'new_order') {
      const { data: o } = await db.from('orders')
        .select('reference,customer_name,customer_phone,total').eq('id', body.order_id).maybeSingle();
      if (!o) return json({ ok: false, error: 'Commande introuvable.' }, 200);
      await toAdmins('🛒 Nouvelle commande', `${o.reference} — ${o.customer_name} — ${fmt(o.total)}`);
      if (o.customer_phone) await toClient(o.customer_phone, '✅ Commande reçue', `Ta commande ${o.reference} est bien reçue. Total ${fmt(o.total)}.`);
      return json({ ok: true });
    }

    if (type === 'status_change') {
      const { data: o } = await db.from('orders')
        .select('reference,customer_phone,status').eq('id', body.order_id).maybeSingle();
      if (!o || !o.customer_phone) return json({ ok: true, skipped: true }, 200);
      const st = String(body.new_status ?? o.status);
      const map: Record<string, [string, string]> = {
        confirmee: ['✅ Commande confirmée', `Ta commande ${o.reference} est confirmée.`],
        en_livraison: ['🚚 En livraison', `Ta commande ${o.reference} est en cours de livraison.`],
        livree: ['📦 Livrée', `Ta commande ${o.reference} est livrée. Merci !`],
        annulee: ['❌ Commande annulée', `Ta commande ${o.reference} a été annulée.`],
      };
      const m = map[st];
      if (!m) return json({ ok: true, skipped: true }, 200);
      await toClient(o.customer_phone, m[0], m[1]);
      return json({ ok: true });
    }

    if (type === 'low_stock') {
      const { data: v } = await db.from('product_variants')
        .select('label,stock_actuel,product:products(name)').eq('id', body.variant_id).maybeSingle();
      if (!v) return json({ ok: false }, 200);
      const name = (v as any).product?.name ?? 'Produit';
      const lbl = v.label && v.label !== 'Standard' ? ` (${v.label})` : '';
      const msg = (v.stock_actuel ?? 0) <= 0 ? `Rupture de stock : ${name}${lbl}` : `Stock faible : ${name}${lbl} — ${v.stock_actuel} restant(s)`;
      await toAdmins('📉 Alerte stock', msg);
      return json({ ok: true });
    }

    if (type === 'new_review') {
      const { data: r } = await db.from('reviews')
        .select('rating,product:products(name)').eq('id', body.review_id).maybeSingle();
      if (!r) return json({ ok: false }, 200);
      await toAdmins('⭐ Nouvel avis', `${r.rating}★ sur ${(r as any).product?.name ?? 'un produit'} — à modérer`);
      return json({ ok: true });
    }

    if (type === 'promo') {
      // Diffusion : réservée au propriétaire authentifié (jeton dans Authorization).
      const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
      const { data: u } = await db.auth.getUser(token);
      if (!u?.user) return json({ ok: false, error: 'Non autorisé.' }, 200);
      const { data: prof } = await db.from('profiles').select('is_owner').eq('id', u.user.id).maybeSingle();
      if (!prof?.is_owner) return json({ ok: false, error: 'Réservé au propriétaire.' }, 200);
      const title = String(body.title ?? 'portable.sn');
      const message = String(body.message ?? '').trim();
      if (!message) return json({ ok: false, error: 'Message vide.' }, 200);
      const r = await osSend({ included_segments: ['Subscribed Users'], headings: { en: title, fr: title }, contents: { en: message, fr: message }, url: body.url || SITE_URL });
      return json({ ok: true, onesignal: r.data });
    }

    return json({ ok: false, error: 'Type inconnu.' }, 400);
  } catch (e) {
    return json({ ok: false, error: 'Erreur envoi notification.' }, 200);
  }
});
