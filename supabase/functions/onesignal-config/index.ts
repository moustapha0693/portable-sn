// onesignal-config : expose UNIQUEMENT l'App ID (public) lu depuis le secret,
// pour que le front n'ait aucune valeur OneSignal écrite en dur.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

Deno.serve((req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const appId = Deno.env.get('ONESIGNAL_APP_ID') ?? '';
  return new Response(JSON.stringify({ appId }), {
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
});
