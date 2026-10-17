const { json, timingSafeEqualText, downloadSignature, supabase, requireMethod } = require('./_lib');
module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, 'GET')) return;
  try {
    const id = String(req.query.id || '');
    const sig = String(req.query.sig || '');
    if (!/^[0-9a-f-]{36}$/i.test(id) || !timingSafeEqualText(sig, downloadSignature(id))) return json(res, 403, { error: 'Invalid download link.' });
    const rows = await supabase(`orders?id=eq.${encodeURIComponent(id)}&select=id,status,product_id`, { method: 'GET' });
    const order = rows && rows[0];
    if (!order || !['paid', 'fulfilled'].includes(order.status) || order.product_id !== 'premium-template-pack') return json(res, 403, { error: 'This product is not available until payment is confirmed.' });
    const projectUrl = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!projectUrl || !key) return json(res, 503, { error: 'Private product storage is not configured.' });
    // Generate a short-lived signed URL from a PRIVATE Supabase Storage bucket.
    const storageResponse = await fetch(projectUrl.replace(/\/$/, '') + '/storage/v1/object/sign/bizkipe-products/bizkipe-premium-template-pack.zip', {
      method: 'POST', headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ expiresIn: 300, download: 'bizkipe-premium-template-pack.zip' })
    });
    const storageData = await storageResponse.json();
    if (!storageResponse.ok || !storageData.signedURL) {
      console.error('Supabase Storage signed URL error:', storageData.message || storageData.error || 'unknown');
      return json(res, 503, { error: 'The download file is not available yet. The site owner must upload the product pack to private storage.' });
    }
    const signed = storageData.signedURL.startsWith('http') ? storageData.signedURL : projectUrl.replace(/\/$/, '') + '/storage/v1' + (storageData.signedURL.startsWith('/') ? storageData.signedURL : '/' + storageData.signedURL);
    res.statusCode = 302;
    res.setHeader('Location', signed);
    res.setHeader('Cache-Control', 'private, no-store');
    return res.end();
  } catch (error) {
    console.error('download error:', error.message);
    return json(res, 503, { error: 'Could not prepare download.' });
  }
};
