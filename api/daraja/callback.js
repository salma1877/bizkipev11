const { json, timingSafeEqualText, supabase, queryStkStatus } = require('../_lib');
module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });
  if (!process.env.DARAJA_CALLBACK_KEY || !timingSafeEqualText(String(req.query.key || ''), process.env.DARAJA_CALLBACK_KEY)) {
    return json(res, 403, { error: 'Forbidden' });
  }
  try {
    const callback = req.body?.Body?.stkCallback;
    if (!callback?.CheckoutRequestID) return json(res, 400, { error: 'Invalid callback payload' });
    const checkoutId = String(callback.CheckoutRequestID);
    const rows = await supabase(`orders?checkout_request_id=eq.${encodeURIComponent(checkoutId)}&select=id,status,amount,product_id`, { method: 'GET' });
    const order = rows && rows[0];
    if (!order) return json(res, 200, { ResultCode: 0, ResultDesc: 'Callback received; no matching order was found.' });
    if (order.status === 'paid') return json(res, 200, { ResultCode: 0, ResultDesc: 'Already processed.' });
    const resultCode = Number(callback.ResultCode);
    const metadata = {};
    for (const item of callback.CallbackMetadata?.Item || []) {
      if (item.Name) metadata[item.Name] = item.Value ?? null;
    }
    const amount = Number(metadata.Amount);
    const receipt = metadata.MpesaReceiptNumber ? String(metadata.MpesaReceiptNumber) : null;
    const phone = metadata.PhoneNumber ? String(metadata.PhoneNumber) : null;
    let status = 'failed';
    let description = String(callback.ResultDesc || 'Payment failed').slice(0, 500);
    if (resultCode === 0 && amount === Number(order.amount) && receipt) {
      // Server-to-server STK query is an additional check; callback data alone is not treated as enough.
      try {
        const query = await queryStkStatus(checkoutId);
        const q = query.data || {};
        const queryResult = q.ResultCode === undefined ? null : Number(q.ResultCode);
        if (query.ok && queryResult === 0) {
          status = 'paid';
          description = 'Payment confirmed by callback and STK query.';
        } else {
          status = 'pending_verification';
          description = 'Successful callback received; STK query requires reconciliation.';
        }
      } catch (e) {
        status = 'pending_verification';
        description = 'Successful callback received; automatic STK query was unavailable and manual reconciliation is required.';
      }
    }
    await supabase(`orders?id=eq.${encodeURIComponent(order.id)}`, {
      method: 'PATCH', headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ status, result_code: resultCode, result_description: description, mpesa_receipt: receipt, paid_amount: Number.isFinite(amount) ? amount : null, payer_phone: phone, callback_payload: req.body, updated_at: new Date().toISOString() })
    });
    return json(res, 200, { ResultCode: 0, ResultDesc: 'Callback processed.' });
  } catch (error) {
    console.error('Daraja callback error:', error.message);
    // Acknowledge safely to avoid callback storms; order remains pending for reconciliation.
    return json(res, 200, { ResultCode: 0, ResultDesc: 'Callback received for reconciliation.' });
  }
};
