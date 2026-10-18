const crypto = require('crypto');
const { json, sha256, normalizePhone, requireMethod, supabase, darajaAccessToken, kenyaTimestamp } = require('../_lib');


  
  const PRODUCTS = {
    'emerald-business': { name: 'Emerald Business', amount: 250, currency: 'KES' },
    'warm-minimal': { name: 'Warm Minimal', amount: 250, currency: 'KES' } // FIXED EMERALD 250,
    'premium-template-pack': { name: 'Emerald Business', amount: 250, currency: 'KES' },
    'bizkipe_templates': { name: 'BizKipe Templates', amount: 250, currency: 'KES' },
    'templates': { name: 'BizKipe Templates', amount: 250, currency: 'KES' },
    'emerald': { name: 'Emerald Business', amount: 250, currency: 'KES' },
    'warm': { name: 'Warm Minimal', amount: 250, currency: 'KES' } // FIXED EMERALD 250,
  };



module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, 'POST')) return;
  try {
    const body = req.body || {};
    console.log('CREATE BODY:', JSON.stringify(body).slice(0,1500));
    let productId = String(body.productId || body.product_id || 'premium-template-pack');
    let product = PRODUCTS[productId];
    if (!product) {
      console.log('Unknown productId', productId, 'using fallback 150');
      product = { name: productId, amount: productId.includes('warm') ? 150 : 250, currency: 'KES' } // FIXED
  // OLD LINE BELOW DISABLED: product = { name: productId, amount: productId.includes('warm') ? 150 : 250, currency: 'KES' } // FIXED
  // OLD LINE BELOW DISABLED: product = { name: productId, amount: productId.includes('warm') ? 150 : 250, currency: 'KES' } // FIXED
  // OLD LINE BELOW DISABLED: product = { name: productId, amount: 250, currency: 'KES' } // FIXED EMERALD 250;
    }
    const name = String(body.name || body.customerName || '').trim().slice(0, 100);
    const email = String(body.email || '').trim().toLowerCase().slice(0, 254);
    const phone = normalizePhone(body.phone || body.phoneNumber || '');
    console.log('Parsed:', { productId, name, email, phone, rawPhone: body.phone });
    if (name.length < 2 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !phone) {
      return json(res, 400, { error: 'Enter your name, a valid email and Kenyan M-Pesa phone.' });
    }
    if (!process.env.APP_URL || !process.env.DARAJA_CALLBACK_KEY) {
      return json(res, 503, { error: 'Checkout is not configured yet.' });
    }
    const orderId = crypto.randomUUID();
    const accessToken = crypto.randomBytes(32).toString('hex');
    await supabase('orders', {
      method: 'POST', headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ id: orderId, product_id: productId, product_name: product.name, customer_name: name, customer_email: email, phone, amount: product.amount, currency: product.currency, status: 'pending', access_token_hash: sha256(accessToken) })
    });
    const { token, host } = await darajaAccessToken();
    const shortcode = process.env.DARAJA_SHORTCODE;
    const storeNumber = process.env.DARAJA_STORE_NUMBER || process.env.STORE_NUMBER || shortcode;
    const passkey = process.env.DARAJA_PASSKEY;
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
      await supabase(`orders?id=eq.${encodeURIComponent(orderId)}`, { method: 'PATCH', body: JSON.stringify({ status: 'failed', result_description: String(data.errorMessage || data.ResponseDescription || 'Daraja rejected').slice(0, 500) }) });
      return json(res, 502, { error: 'Daraja could not start the payment prompt. ' + String(data.errorMessage || data.ResponseDescription || ''), details: data });
    }
    try {
      await supabase(`orders?id=eq.${encodeURIComponent(orderId)}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ checkout_request_id: data.CheckoutRequestID, merchant_request_id: data.MerchantRequestID || null, updated_at: new Date().toISOString() }) });
    } catch(e){ console.log('save ids failed, ok'); }
    return json(res, 200, { orderId, accessToken, message: 'M-Pesa payment prompt requested. Check your phone and complete payment in the official M-Pesa prompt.' });
  } catch (error) {
    console.error('create-order error:', error.message);
    return json(res, 503, { error: error.message.includes('not configured') || error.message.includes('Database') ? error.message : 'Checkout could not be started. Please try again later.' });
  }
};
