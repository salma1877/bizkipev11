const { json, adminGuard, logActivity, supabase } = require('../_lib');

function cell(v) {
  if (v === null || v === undefined) return '""';
  if (typeof v === 'number') return String(v);
  let s = String(v);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;          // stop spreadsheet formulas from running
  return '"' + s.replace(/"/g, '""') + '"';
}

module.exports = async function handler(req, res) {
  if (!(await adminGuard(req, res))) return;
  if (req.method !== 'GET') return json(res, 405, { error: 'Method not allowed' });
  if (String((req.query && req.query.type) || 'orders') !== 'orders') return json(res, 400, { error: 'Unsupported export.' });
  try {
    const rows = await supabase('orders?select=created_at,status,product_name,customer_name,customer_email,phone,amount,currency,paid_amount,mpesa_receipt&order=created_at.desc&limit=5000', { method: 'GET' }) || [];
    const cols = ['created_at', 'status', 'product_name', 'customer_name', 'customer_email', 'phone', 'amount', 'currency', 'paid_amount', 'mpesa_receipt'];
    const csv = '﻿' + [cols.map(cell).join(',')].concat(rows.map((r) => cols.map((c) => cell(r[c])).join(','))).join('\r\n') + '\r\n';
    await logActivity(req, 'orders_exported', rows.length + ' orders downloaded as CSV', null, true);
    res.status(200);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="bizkipe-orders.csv"');
    res.setHeader('Cache-Control', 'no-store');
    return res.end(csv);
  } catch (error) {
    console.error('admin export error:', error.message);
    return json(res, 503, { error: 'Could not prepare the export.' });
  }
};
