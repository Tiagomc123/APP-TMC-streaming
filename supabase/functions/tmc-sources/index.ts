import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'GET') {
    return Response.json({ ok: false, error: 'method_not_allowed' }, { status: 405, headers: cors });
  }

  try {
    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data, error } = await db
      .from('tmc_sources')
      .select('id, urls')
      .eq('enabled', true);
    if (error) throw error;

    const domains: Record<string, string[]> = {};
    for (const row of data ?? []) {
      const urls = (row.urls ?? []).filter((value: unknown): value is string => {
        if (typeof value !== 'string') return false;
        try {
          const url = new URL(value);
          return url.protocol === 'https:' && url.hostname.length > 0 &&
            url.username === '' && url.password === '' &&
            url.pathname === '/' && url.search === '' && url.hash === '';
        } catch {
          return false;
        }
      });
      if (urls.length > 0) domains[row.id] = urls;
    }

    return Response.json(
      { ok: true, updated: new Date().toISOString(), domains },
      { headers: { ...cors, 'Cache-Control': 'public, max-age=60' } },
    );
  } catch (error) {
    console.error('tmc-sources failed', error);
    return Response.json(
      { ok: false, error: 'source_registry_unavailable' },
      { status: 503, headers: cors },
    );
  }
});
