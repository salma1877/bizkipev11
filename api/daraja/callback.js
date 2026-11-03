const { json, supabase } = require('../_lib');

// Safaricom calls this URL after the customer answers the STK push.
// Rules: match the order ONLY by CheckoutRequestID, never guess; only mark an order
// paid when M-Pesa reports success with a receipt and an amount that covers the order;
// anything doubtful goes to "pending_verification" for the owner to check by hand.
module.exports = async function handler(req, res) {
  const key = String(req.query.key || '');
  if (!process.env.DARAJA_CALLBACK_KEY || key !== String(process.env.DARAJA_CALLBACK_KEY)) {
    return json(res, 401, { error: 'Invalid callback key' });
  }
  const accepted = () => json(res, 200, { ResultCode: 0, ResultDesc: 'Accepted' });
  try {
    const body = req.body || {};
    const cb = body.Body && body.Body.stkCallback;
    if (!cb || !cb.CheckoutRequestID) return accepted();

    const checkoutId = String(cb.CheckoutRequestID);
    const resultCode = Number(cb.ResultCode);
    const resultDesc = String(cb.ResultDesc || '').slice(0, 500);

    const rows = await supabase(`orders?checkout_request_id=eq.${encodeURIComponent(checkoutId)}&select=id,status,amount`, { method: 'GET' });
    const order = Array.isArray(rows) ? rows[0] : null;
    if (!order) { console.log('Callback for unknown checkout id'); return accepted(); }
    // Only a still-waiting order can change. Never overwrite paid, fulfilled or failed orders.
    if (order.status !== 'pending') return accepted();

    const patch = (data) => supabase(`orders?id=eq.${encodeURIComponent(order.id)}&status=eq.pending`, {
      method: 'PATCH', headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ ...data, result_code: Number.isFinite(resultCode) ? resultCode : null, result_description: resultDesc, updated_at: new Date().toISOString() })
    });

    if (resultCode !== 0) {
      await patch({ status: 'failed' });
      return accepted();
    }

    const items = (cb.CallbackMetadata && cb.CallbackMetadata.Item) || [];
    const pick = (name) => { const it = items.find(i => i && i.Name === name); return it ? it.Value : null; };
    const receipt = String(pick('MpesaReceiptNumber') || '').trim().toUpperCase();
    const paidAmount = Number(pick('Amount'));
    const payer = pick('PhoneNumber') ? String(pick('PhoneNumber')) : null;
    const validReceipt = /^[A-Z0-9]{8,12}$/.test(receipt);
    const covers = Number.isFinite(paidAmount) && paidAmount >= Number(order.amount);

    let duplicate = false;
    if (validReceipt) {
      const same = await supabase(`orders?mpesa_receipt=eq.${encodeURIComponent(receipt)}&select=id&limit=1`, { method: 'GET' });
      duplicate = Array.isArray(same) && same.length > 0;
    }

    if (validReceipt && covers && !duplicate) {
      await patch({ status: 'paid', mpesa_receipt: receipt, paid_amount: paidAmount, payer_phone: payer });
    } else {
      // Needs a human check against the official M-Pesa record (admin page: "Verify manually").
      await patch({ status: 'pending_verification', mpesa_receipt: validReceipt && !duplicate ? receipt : null, paid_amount: Number.isFinite(paidAmount) ? paidAmount : null, payer_phone: payer });
    }
    return accepted();
  } catch (e) {
    console.error('Daraja callback error:', e.message);
    return accepted();
  }
};
