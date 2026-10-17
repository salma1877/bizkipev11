const { json, requireMethod, adminAuthorized, supabase } = require('../_lib');
module.exports = async function handler(req, res) {
  if (!adminAuthorized(req)) return json(res, 401, { error: 'Unauthorized' });
  try {
    if (req.method === 'GET') {
      const rows = await supabase('orders?select=id,created_at,updated_at,product_name,customer_name,customer_email,phone,amount,currency,status,mpesa_receipt,paid_amount,result_description&order=created_at.desc&limit=200', { method: 'GET' });
      return json(res, 200, { orders: rows || [] });
    }
    if (!requireMethod(req, res, 'POST')) return;
    const body = req.body || {};
    const id = String(body.id || '');
    const action = String(body.action || '');
    if (!/^[0-9a-f-]{36}$/i.test(id)) return json(res, 400, { error: 'Invalid order ID.' });
    const found = await supabase(`orders?id=eq.${encodeURIComponent(id)}&select=id,status,amount,paid_amount,mpesa_receipt`, { method: 'GET' });
    const order = found && found[0];
    if (!order) return json(res, 404, { error: 'Order not found.' });
    if (action === 'confirm_manual_payment') {
      const receipt = String(body.receipt || '').trim().toUpperCase();
      const amount = Number(body.amount);
      if (order.status !== 'pending_verification' || !receipt || !Number.isFinite(amount) || amount !== Number(order.amount)) {
        return json(res, 400, { error: 'Only pending-verification orders can be manually confirmed, and the amount must match the order total.' });
      }
      await supabase(`orders?id=eq.${encodeURIComponent(id)}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ status: 'paid', mpesa_receipt: receipt, paid_amount: amount, result_description: 'Manually reconciled by admin against the official M-Pesa transaction record.', updated_at: new Date().toISOString() }) });
      return json(res, 200, { ok: true });
    }
    if (action === 'mark_fulfilled') {
      if (order.status !== 'paid') return json(res, 400, { error: 'Only paid orders can be marked fulfilled.' });
      await supabase(`orders?id=eq.${encodeURIComponent(id)}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ status: 'fulfilled', updated_at: new Date().toISOString() }) });
      return json(res, 200, { ok: true });
    }
    return json(res, 400, { error: 'Unsupported admin action.' });
  } catch (error) {
    console.error('admin orders error:', error.message);
    return json(res, 503, { error: 'Admin request failed. Check database configuration.' });
  }
};
