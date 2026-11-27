const { json, adminGuard, logActivity, supabase } = require('../_lib');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Every table that holds one customer's own records (all are removed automatically when the account is deleted).
const USER_TABLES = ['saved_documents', 'bizkipe_inventory_items', 'bizkipe_inventory_movements', 'bizkipe_inventory_sales',
  'bizkipe_financial_entries', 'bizkipe_financial_payments', 'bizkipe_customer_followups', 'bizkipe_loyalty_settings',
  'bizkipe_loyalty_redemptions', 'bizkipe_recurring_schedules', 'bizkipe_invoice_shares', 'bizkipe_customer_portal_links',
  'bizkipe_quote_approval_links', 'bizkipe_workflow_rules', 'bizkipe_workflow_activity', 'bizkipe_notification_preferences',
  'bizkipe_customer_campaigns', 'bizkipe_campaign_engagement_events', 'bizkipe_retention_plans', 'bizkipe_customer_feedback',
  'bizkipe_customer_issues', 'bizkipe_feedback_portal_links', 'bizkipe_suppliers', 'bizkipe_purchase_orders'];
const COUNT_TABLES = [['saved_documents', 'Saved documents'], ['bizkipe_financial_entries', 'Income and expense records'],
  ['bizkipe_financial_payments', 'Payment records'], ['bizkipe_inventory_items', 'Stock items'],
  ['bizkipe_suppliers', 'Suppliers'], ['bizkipe_customer_followups', 'Customer follow-ups']];

function creds() {
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('Database is not configured.');
  return { url: url.replace(/\/$/, ''), key };
}
async function auth(path, options) {
  const { url, key } = creds();
  const r = await fetch(url + '/auth/v1/' + path, { ...(options || {}), headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' } });
  const text = await r.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  return { ok: r.ok, status: r.status, data };
}
async function countRows(table, id) {
  try {
    const { url, key } = creds();
    const r = await fetch(url + '/rest/v1/' + table + '?user_id=eq.' + id + '&select=user_id', { method: 'HEAD', headers: { apikey: key, Authorization: 'Bearer ' + key, Prefer: 'count=exact' } });
    if (!r.ok) return null;
    const n = Number(String(r.headers.get('content-range') || '').split('/')[1]);
    return Number.isFinite(n) ? n : null;
  } catch { return null; }
}
function publicUser(u) {
  return {
    id: u.id, email: u.email || '', created_at: u.created_at || null, last_sign_in_at: u.last_sign_in_at || null,
    suspended: !!(u.banned_until && new Date(u.banned_until).getTime() > Date.now()),
    confirmed: !!(u.email_confirmed_at || u.confirmed_at)
  };
}
function maskEmail(email) {
  const [name, domain] = String(email || '').split('@');
  return (name ? name[0] : '') + '***' + (domain ? '@' + domain : '');
}
function who(u) { return maskEmail(u.email) + ' (' + String(u.id).slice(0, 8) + ')'; }

async function listUsers(q) {
  const all = [];
  for (let page = 1; page <= 5; page++) {
    const r = await auth('admin/users?page=' + page + '&per_page=200');
    if (!r.ok) throw new Error('Could not load users.');
    const batch = (r.data && Array.isArray(r.data.users)) ? r.data.users : [];
    all.push(...batch);
    if (batch.length < 200) break;
  }
  const term = String(q || '').trim().toLowerCase();
  let rows = all.map(publicUser);
  if (term) rows = rows.filter(u => u.email.toLowerCase().includes(term) || u.id === term);
  rows.sort((a, b) => new Date(b.last_sign_in_at || b.created_at || 0) - new Date(a.last_sign_in_at || a.created_at || 0));
  return { users: rows.slice(0, 25), matched: rows.length, scanned: all.length };
}

module.exports = async function handler(req, res) {
  if (!(await adminGuard(req, res))) return;
  try {
    if (req.method === 'GET') {
      const id = String((req.query && req.query.id) || '');
      if (id) {
        if (!UUID.test(id)) return json(res, 400, { error: 'Invalid user.' });
        const r = await auth('admin/users/' + id);
        if (!r.ok || !r.data) return json(res, 404, { error: 'User not found.' });
        const counts = await Promise.all(COUNT_TABLES.map(async ([t, label]) => ({ label, count: await countRows(t, id) })));
        return json(res, 200, { user: publicUser(r.data), counts });
      }
      return json(res, 200, await listUsers(req.query && req.query.q));
    }
    if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });
    const body = req.body || {};
    const id = String(body.id || ''), action = String(body.action || '');
    if (!UUID.test(id)) return json(res, 400, { error: 'Invalid user.' });
    const found = await auth('admin/users/' + id);
    if (!found.ok || !found.data) return json(res, 404, { error: 'User not found.' });
    const user = found.data;

    if (action === 'suspend' || action === 'restore') {
      const r = await auth('admin/users/' + id, { method: 'PUT', body: JSON.stringify({ ban_duration: action === 'suspend' ? '876000h' : 'none' }) });
      if (!r.ok) return json(res, 502, { error: 'Could not change the account. Try again.' });
      await logActivity(req, action === 'suspend' ? 'user_suspended' : 'user_restored', who(user), null, true);
      return json(res, 200, { ok: true });
    }
    if (action === 'export') {
      const tables = {}, skipped = [];
      await Promise.all(USER_TABLES.map(async (t) => {
        try { tables[t] = await supabase(t + '?user_id=eq.' + id + '&select=*&limit=5000', { method: 'GET' }) || []; }
        catch { skipped.push(t); }
      }));
      let orders = [];
      try {
        const op = /[*%_\\]/.test(user.email || '') ? 'eq' : 'ilike';
        orders = await supabase('orders?customer_email=' + op + '.' + encodeURIComponent(user.email || '') + '&select=id,created_at,product_name,amount,currency,status,mpesa_receipt&order=created_at.desc&limit=500', { method: 'GET' }) || [];
      } catch { orders = []; }
      await logActivity(req, 'user_exported', who(user), null, true);
      return json(res, 200, {
        exported_at: new Date().toISOString(), account: publicUser(user), tables, tables_not_available: skipped, orders,
        note: 'Order and payment records may be kept for accounting, dispute and security purposes.'
      });
    }
    if (action === 'delete') {
      const typed = String(body.confirm_email || '').trim().toLowerCase();
      if (!user.email || typed !== String(user.email).toLowerCase()) return json(res, 400, { error: 'The email you typed does not match this account. Nothing was deleted.' });
      const r = await auth('admin/users/' + id, { method: 'DELETE' });
      if (!r.ok) {
        await logActivity(req, 'user_delete_failed', who(user), null, false);
        return json(res, 502, { error: 'The account could not be deleted. Nothing was changed.' });
      }
      await logActivity(req, 'user_deleted', who(user), null, true);
      return json(res, 200, { ok: true });
    }
    return json(res, 400, { error: 'Unsupported action.' });
  } catch (error) {
    console.error('admin users error:', error.message);
    return json(res, 503, { error: 'Admin request failed. Check database configuration.' });
  }
};
