const crypto = require('crypto');
const { json, sha256, normalizePhone, requireMethod, supabase, darajaAccessToken, kenyaTimestamp } = require('../_lib');

const PRODUCTS = {
  'premium-template-pack': { name: 'Premium Template Pack', amount: 150, currency: 'KES' },
};

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, 'POST')) return;
  try {
    const body = req.body || {};
    const product = PRODUCTS[String(body.productId || '')];
    const name = String(body.name || '').trim().slice(0, 100);
    const email = String(body.email || '').trim().toLowerCase().slice(0, 254);
    const phone = normalizePhone(body.phone);
    if (!product) return json(res, 400, { error: 'Unknown product.' });
    if (name.length < 2 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !phone) {
      return json(res, 400, { error: 'Enter your name, a valid email address and a Kenyan M-Pesa phone number.' });
    }
    if (!process.env.APP_URL || !process.env.DARAJA_CALLBACK_KEY) {
      return json(res, 503, { error: 'Checkout is not configured yet. The site owner must configure the secure server environment first.' });
    }
    if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY || !process.env.DARAJA_CONSUMER_KEY || !process.env.DARAJA_CONSUMER_SECRET || !process.env.DARAJA_SHORTCODE || !process.env.DARAJA_PASSKEY || !process.env.DOWNLOAD_SECRET) {
      return json(res, 503, { error: 'Checkout setup is incomplete. The site owner must finish database, download and Daraja configuration before accepting orders.' });
    }
    const orderId = crypto.randomUUID();
    const accessToken = crypto.randomBytes(32).toString('hex');
    await supabase('orders', {
      method: 'POST', headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({
        id: orderId, product_id: body.productId, product_name: product.name,
        customer_name: name, customer_email: email, phone,
        amount: product.amount, currency: product.currency, status: 'pending', access_token_hash: sha256(accessToken)
      })
    });

    const { token, host } = await darajaAccessToken();
    const shortcode = process.env.DARAJA_SHORTCODE;
    const storeNumber = process.env.DARAJA_STORE_NUMBER || process.env.STORE_NUMBER || shortcode;
    const passkey = process.env.DARAJA_PASSKEY;
    if (!shortcode || !passkey) throw new Error('Daraja shortcode/passkey are not configured.');
    const timestamp = kenyaTimestamp();
    const password = Buffer.from(shortcode + passkey + timestamp).toString('base64');
    const callbackUrl = `${process.env.APP_URL.replace(/\/$/, '')}/api/daraja/callback?key=${encodeURIComponent(process.env.DARAJA_CALLBACK_KEY)}`;
    const transactionType = process.env.DARAJA_TRANSACTION_TYPE || 'CustomerBuyGoodsOnline';
    const payload = {
      BusinessShortCode: shortcode,
      Password: password,
      Timestamp: timestamp,
      TransactionType: transactionType,
      Amount: product.amount,
      PartyA: phone,
      PartyB: storeNumber,
      PhoneNumber: phone,
      CallBackURL: callbackUrl,
      AccountReference: ('BK' + orderId.replace(/-/g, '').slice(0, 10)).slice(0, 12),
      TransactionDesc: 'BizKipe template pack'
    };
    console.log('STK Payload:', JSON.stringify({ BusinessShortCode: payload.BusinessShortCode, PartyB: payload.PartyB, TransactionType: payload.TransactionType, Amount: payload.Amount, PartyA: payload.PartyA }));
    const response = await fetch(host + '/mpesa/stkpush/v1/processrequest', {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    });
    const data = await response.json();
    console.log('Daraja STK Response:', JSON.stringify(data));
    if (!response.ok || data.ResponseCode !== '0' || !data.CheckoutRequestID) {
      await supabase(`orders?id=eq.${encodeURIComponent(orderId)}`, { method: 'PATCH', body: JSON.stringify({ status: 'failed', result_description: String(data.errorMessage || data.ResponseDescription || 'Daraja rejected the payment request').slice(0, 500) }) });
      return json(res, 502, { error: 'Daraja could not start the payment prompt. ' + String(data.errorMessage || data.ResponseDescription || ''), details: data });
    }
    await supabase(`orders?id=eq.${encodeURIComponent(orderId)}`, {
      method: 'PATCH', headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ checkout_request_id: data.CheckoutRequestID, merchant_request_id: data.MerchantRequestID || null, updated_at: new Date().toISOString() })
    });
    return json(res, 200, { orderId, accessToken, message: 'M-Pesa payment prompt requested. Check your phone and complete payment in the official M-Pesa prompt.' });
  } catch (error) {
    console.error('create-order error:', error.message);
    return json(res, 503, { error: error.message.includes('not configured') || error.message.includes('Database') ? error.message : 'Checkout could not be started. Please try again later.' });
  }
};
