const { json, sha256, timingSafeEqualText, downloadSignature, requireMethod, supabase } = require('../_lib');
module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, 'GET')) return;
  try {
    const id = String(req.query.id || '');
    const accessToken = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (!/^[0-9a-f-]{36}$/i.test(id) || !accessToken) return json(res, 400, { error: 'Invalid order reference.' });
    const rows = await supabase(`orders?id=eq.${encodeURIComponent(id)}&select=id,status,access_token_hash,product_id`, { method: 'GET' });
    const order = rows && rows[0];
    if (!order || !timingSafeEqualText(order.access_token_hash, sha256(accessToken))) return json(res, 404, { error: 'Order not found.' });
    const out = { status: order.status };
    if (order.status === 'paid' && order.product_id === 'premium-template-pack') {
      const sig = downloadSignature(order.id);
      out.downloadUrl = `/api/download?id=${encodeURIComponent(order.id)}&sig=${encodeURIComponent(sig)}`;
    }
    return json(res, 200, out);
  } catch (error) {
    console.error('order status error:', error.message);
    return json(res, 503, { error: 'Could not check order status right now.' });
  }
};
