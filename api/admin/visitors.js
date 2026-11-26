const { json, adminGuard, supabase } = require('../_lib');

function nairobiStartOfToday() {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Nairobi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  return new Date(parts + 'T00:00:00+03:00');
}
function shortId(id) { return String(id).slice(0, 6); }

async function registeredUsers() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  try {
    const r = await fetch(url.replace(/\/$/, '') + '/auth/v1/admin/users?page=1&per_page=200', { headers: { apikey: key, Authorization: 'Bearer ' + key } });
    if (!r.ok) return null;
    const data = await r.json();
    const list = Array.isArray(data.users) ? data.users : [];
    const total = Number(r.headers.get('x-total-count')) || Number(data.total) || list.length;
    list.sort((a, b) => new Date(b.last_sign_in_at || b.created_at || 0) - new Date(a.last_sign_in_at || a.created_at || 0));
    return {
      total,
      recent: list.slice(0, 15).map(u => ({ email: u.email || '', created_at: u.created_at || null, last_sign_in_at: u.last_sign_in_at || null }))
    };
  } catch { return null; }
}

module.exports = async function handler(req, res) {
  if (!(await adminGuard(req, res))) return;
  if (req.method !== 'GET') return json(res, 405, { error: 'Method not allowed' });
  try {
    const now = Date.now();
    const since30 = new Date(now - 30 * 86400000).toISOString();
    const rows = await supabase('site_visitors?select=visitor_id,first_seen,last_seen,last_page,is_app,app_installed_at,signed_in&last_seen=gte.' + encodeURIComponent(since30) + '&order=last_seen.desc&limit=5000', { method: 'GET' }) || [];
    const appRows = await supabase('site_visitors?select=visitor_id,is_app,app_installed_at&or=(is_app.eq.true,app_installed_at.not.is.null)&limit=5000', { method: 'GET' }) || [];
    const t = (r) => new Date(r.last_seen).getTime();
    const onlineCut = now - 3 * 60000, dayCut = nairobiStartOfToday().getTime(), weekCut = now - 7 * 86400000;
    const online = rows.filter(r => t(r) >= onlineCut);
    const pages = {};
    online.forEach(r => { pages[r.last_page] = (pages[r.last_page] || 0) + 1; });
    const topPages = Object.entries(pages).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([page, count]) => ({ page, count }));
    const stats = {
      online_now: online.length,
      online_in_app: online.filter(r => r.is_app).length,
      online_signed_in: online.filter(r => r.signed_in).length,
      today: rows.filter(r => t(r) >= dayCut).length,
      last_7_days: rows.filter(r => t(r) >= weekCut).length,
      last_30_days: rows.length,
      new_today: rows.filter(r => new Date(r.first_seen).getTime() >= dayCut).length,
      app_opened_ever: appRows.filter(r => r.is_app).length,
      app_opened_7_days: rows.filter(r => r.is_app && t(r) >= weekCut).length,
      installs_recorded: appRows.filter(r => r.app_installed_at).length
    };
    const recent = rows.slice(0, 15).map(r => ({ id: shortId(r.visitor_id), last_seen: r.last_seen, page: r.last_page, in_app: !!r.is_app, signed_in: !!r.signed_in }));
    const users = await registeredUsers();
    return json(res, 200, { stats, top_pages: topPages, recent, users, truncated: rows.length >= 5000 });
  } catch (error) {
    console.error('admin visitors error:', error.message);
    return json(res, 503, { error: 'Could not load visitor numbers. Check that the visitors SQL has been applied.' });
  }
};
