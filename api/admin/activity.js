const { json, adminGuard, logActivity, supabase } = require('../_lib');

module.exports = async function handler(req, res) {
  if (!(await adminGuard(req, res))) return;
  if (req.method === 'POST') {
    const action = String((req.body || {}).action || '');
    if (action !== 'signin') return json(res, 400, { error: 'Unsupported action.' });
    await logActivity(req, 'admin_signin', 'Signed in to the admin page', null, true);
    return json(res, 200, { ok: true });
  }
  if (req.method !== 'GET') return json(res, 405, { error: 'Method not allowed' });
  try {
    const since = new Date(Date.now() - 24 * 3600000).toISOString();
    const activity = await supabase('admin_activity?select=id,created_at,action,detail,order_id,success&action=neq.login_failed&order=created_at.desc&limit=50', { method: 'GET' }) || [];
    const failed = await supabase('admin_activity?select=created_at&action=eq.login_failed&created_at=gte.' + encodeURIComponent(since) + '&order=created_at.desc&limit=200', { method: 'GET' }) || [];
    return json(res, 200, { activity, failed_logins_24h: failed.length, last_failed_login: failed[0] ? failed[0].created_at : null });
  } catch (error) {
    console.error('admin activity error:', error.message);
    return json(res, 200, { activity: [], failed_logins_24h: 0, last_failed_login: null, setup_needed: true });
  }
};
