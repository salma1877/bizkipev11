const { json, supabase } = require('../_lib');
module.exports = async function handler(req, res) {
  const key = String(req.query.key || '');
  if (key !== String(process.env.DARAJA_CALLBACK_KEY || '')) {
    return json(res, 401, { error: 'Invalid callback key' });
  }
  try {
    const body = req.body || {};
    console.log('Daraja callback body:', JSON.stringify(body).slice(0,2000));
    const cb = body.Body?.stkCallback;
    if (!cb) return json(res, 200, { ok: true });

    const checkoutId = cb.CheckoutRequestID;
    const merchantId = cb.MerchantRequestID;
    const resultCode = cb.ResultCode;
    const resultDesc = cb.ResultDesc || '';

    // Find order
    let orderQuery = checkoutId ? `checkout_request_id=eq.${encodeURIComponent(checkoutId)}` : `merchant_request_id=eq.${encodeURIComponent(merchantId)}`;
    let orderRes = await supabase(`orders?${orderQuery}&select=id,status`, { method: 'GET' });
    let orders = await orderRes.json();
    if (!orders || orders.length === 0) {
      // fallback: search by most recent pending
      let recent = await supabase(`orders?status=eq.pending&order=created_at.desc&limit=1&select=id`, { method: 'GET' });
      orders = await recent.json();
    }
    if (!orders || orders.length === 0) {
      console.log('No order found for callback', checkoutId);
      return json(res, 200, { ok: true });
    }
    const orderId = orders[0].id;

    if (resultCode === 0) {
      const meta = cb.CallbackMetadata?.Item || [];
      const receiptItem = meta.find(i => i.Name === 'MpesaReceiptNumber');
      const receipt = receiptItem ? receiptItem.Value : null;
      await supabase(`orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ 
          status: 'paid', 
          mpesa_receipt_number: receipt,
          result_code: resultCode,
          result_description: resultDesc.slice(0,500),
          paid_at: new Date().toISOString()
        })
      });
    } else {
      await supabase(`orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ 
          status: 'failed', 
          result_code: resultCode,
          result_description: resultDesc.slice(0,500),
          fail_reason: resultDesc.slice(0,500)
        })
      });
    }
    return json(res, 200, { ResultCode: 0, ResultDesc: 'Accepted' });
  } catch (e) {
    console.error('Daraja callback error:', e.message);
    return json(res, 200, { ResultCode: 0, ResultDesc: 'Accepted' });
  }
};
