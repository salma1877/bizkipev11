const crypto = require('crypto');

function json(res, status, body) {
  res.status(status).setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  return res.end(JSON.stringify(body));
}
function timingSafeEqualText(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const aa = Buffer.from(a); const bb = Buffer.from(b);
  return aa.length === bb.length && crypto.timingSafeEqual(aa, bb);
}
function sha256(value) { return crypto.createHash('sha256').update(value).digest('hex'); }
function downloadSignature(orderId) {
  if (!process.env.DOWNLOAD_SECRET) throw new Error('DOWNLOAD_SECRET is not configured');
  return crypto.createHmac('sha256', process.env.DOWNLOAD_SECRET).update(orderId).digest('hex');
}
function normalizePhone(value) {
  const digits = String(value || '').replace(/\D/g, '');
  let p = digits;
  if (p.startsWith('0')) p = '254' + p.slice(1);
  if (p.startsWith('7') || p.startsWith('1')) p = '254' + p;
  if (!/^254[71]\d{8}$/.test(p)) return null;
  return p;
}
function requireMethod(req, res, method) {
  if (req.method !== method) { json(res, 405, { error: 'Method not allowed' }); return false; }
  return true;
}
function adminAuthorized(req) {
  const token = process.env.ADMIN_TOKEN;
  const supplied = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  return !!token && timingSafeEqualText(supplied, token);
}
async function supabase(path, options = {}) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('Database is not configured. Add Supabase environment variables in Vercel.');
  const response = await fetch(url.replace(/\/$/, '') + '/rest/v1/' + path, {
    ...options,
    headers: {
      apikey: key,
      Authorization: 'Bearer ' + key,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    }
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { message: text }; }
  if (!response.ok) throw new Error(data?.message || data?.error || 'Database request failed');
  return data;
}
function clientHash(req) {
  const ip = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || 'unknown';
  return sha256(ip + ':' + (process.env.ADMIN_TOKEN || '')).slice(0, 16);
}
// Writes one line to the admin activity log. Never throws: logging must not break an admin action.
async function logActivity(req, action, detail, orderId, success) {
  try {
    await supabase('admin_activity', {
      method: 'POST',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ action, detail: String(detail || '').slice(0, 300), order_id: orderId || null, success: success !== false, ip_hash: clientHash(req) })
    });
  } catch (error) { console.error('activity log error:', error.message); }
}
// Admin gate: five wrong tokens from one address lock it out for 10 minutes.
// If the log table is not set up yet it fails open, so the admin page keeps working.
async function adminGuard(req, res) {
  const hash = clientHash(req);
  let logReady = true;
  try {
    const since = new Date(Date.now() - 10 * 60000).toISOString();
    const rows = await supabase('admin_activity?select=id&action=eq.login_failed&ip_hash=eq.' + hash + '&created_at=gte.' + encodeURIComponent(since) + '&limit=5', { method: 'GET' });
    if (Array.isArray(rows) && rows.length >= 5) {
      json(res, 429, { error: 'Too many wrong attempts. Please wait 10 minutes and try again.' });
      return false;
    }
  } catch (error) { logReady = false; }
  if (adminAuthorized(req)) return true;
  const supplied = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (logReady && supplied) await logActivity(req, 'login_failed', 'Wrong admin token', null, false);
  json(res, 401, { error: 'Unauthorized' });
  return false;
}
async function darajaAccessToken() {
  const key = process.env.DARAJA_CONSUMER_KEY;
  const secret = process.env.DARAJA_CONSUMER_SECRET;
  if (!key || !secret) throw new Error('Daraja credentials are not configured yet.');
  const host = process.env.DARAJA_ENV === 'production' ? 'https://api.safaricom.co.ke' : 'https://sandbox.safaricom.co.ke';
  const response = await fetch(host + '/oauth/v1/generate?grant_type=client_credentials', {
    headers: { Authorization: 'Basic ' + Buffer.from(key + ':' + secret).toString('base64') }
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) throw new Error('Could not authenticate with Daraja. Check credentials and environment.');
  return { token: data.access_token, host };
}
function kenyaTimestamp() {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Nairobi', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23'
  }).formatToParts(new Date());
  const p = Object.fromEntries(parts.map(x => [x.type, x.value]));
  return `${p.year}${p.month}${p.day}${p.hour}${p.minute}${p.second}`;
}
async function queryStkStatus(checkoutRequestId) {
  const { token, host } = await darajaAccessToken();
  const shortcode = process.env.DARAJA_SHORTCODE;
  const passkey = process.env.DARAJA_PASSKEY;
  if (!shortcode || !passkey) throw new Error('Daraja shortcode/passkey are not configured.');
  const timestamp = kenyaTimestamp();
  const password = Buffer.from(shortcode + passkey + timestamp).toString('base64');
  const response = await fetch(host + '/mpesa/stkpushquery/v1/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ BusinessShortCode: shortcode, Password: password, Timestamp: timestamp, CheckoutRequestID: checkoutRequestId })
  });
  const data = await response.json();
  return { ok: response.ok, data };
}
module.exports = { adminGuard, logActivity, clientHash, json, timingSafeEqualText, sha256, downloadSignature, normalizePhone, requireMethod, adminAuthorized, supabase, darajaAccessToken, kenyaTimestamp, queryStkStatus };
