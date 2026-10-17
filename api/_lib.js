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
module.exports = { json, timingSafeEqualText, sha256, downloadSignature, normalizePhone, requireMethod, adminAuthorized, supabase, darajaAccessToken, kenyaTimestamp, queryStkStatus };
