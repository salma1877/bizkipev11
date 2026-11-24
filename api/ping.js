const { json, supabase } = require('./_lib');

// Best-effort throttle per server instance: a single address can send at most 40 signals a minute.
const hits = new Map();
function throttled(ip) {
  const now = Date.now();
  const entry = hits.get(ip);
  if (!entry || now - entry.start > 60000) { hits.set(ip, { start: now, n: 1 }); return false; }
  entry.n += 1;
  if (hits.size > 5000) hits.clear();
  return entry.n > 40;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });
  const origin = String(req.headers.origin || '');
  if (origin) {
    try { if (new URL(origin).host !== req.headers.host) return json(res, 403, { error: 'Not allowed' }); }
    catch { return json(res, 403, { error: 'Not allowed' }); }
  }
  const ip = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || 'unknown';
  if (throttled(ip)) return json(res, 429, { error: 'Too many requests' });
  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const vid = String(body.vid || '');
  if (!/^[A-Za-z0-9-]{16,64}$/.test(vid)) return json(res, 400, { error: 'Invalid request' });
  let page = String(body.page || '/').split(/[?#]/)[0];
  if (!page.startsWith('/')) page = '/';
  page = page.slice(0, 80);
  const row = { visitor_id: vid, last_seen: new Date().toISOString(), last_page: page };
  // Only ever switch these on, so a later browser visit never erases an earlier app visit.
  if (body.app === true) row.is_app = true;
  if (body.installed === true) row.app_installed_at = new Date().toISOString();
  if (body.signedIn === true) row.signed_in = true;
  try {
    await supabase('site_visitors?on_conflict=visitor_id', {
      method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(row)
    });
    return json(res, 200, { ok: true });
  } catch (error) {
    console.error('ping error:', error.message);
    return json(res, 200, { ok: false });
  }
};
