export default async function handler(req, res) {
  function json(r,c,o){ r.statusCode=c; r.setHeader('Content-Type','application/json'); r.end(JSON.stringify(o)); }
  async function supabase(path, opts={}) {
    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if(!url||!key) throw new Error('no supabase env');
    const r = await fetch(url.replace(/\/$/,'')+'/rest/v1/'+path, {
      ...opts,
      headers: { apikey: key, Authorization: 'Bearer '+key, 'Content-Type':'application/json', ...(opts.headers||{}) }
    });
    const t = await r.text();
    try{ return JSON.parse(t); }catch{ return t; }
  }
  try{
    const q = req.query;
    const id = q.orderId || q.order_id || q.id;
    if(!id) return json(res,400,{error:'Missing order id'});
    
    // The order must be a real UUID, paid for in full, and carry a genuine M-Pesa receipt.
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(id))) return json(res,400,{error:'Invalid order reference.'});
    const rows = await supabase(`orders?id=eq.${encodeURIComponent(id)}&select=id,status,product_id,amount,paid_amount,mpesa_receipt`, { method: 'GET' });
    const order = Array.isArray(rows) ? rows[0] : null;
    const notReady = () => json(res,403,{error:'This product is not available until payment is confirmed.'});
    if(!order || !['paid','fulfilled'].includes(order.status) || order.product_id !== 'premium-template-pack') return notReady();
    const receipt = String(order.mpesa_receipt || '').trim();
    const amount = Number(order.amount);
    const paidAmount = Number(order.paid_amount);
    if(!/^[A-Z0-9]{8,12}$/i.test(receipt) || !Number.isFinite(amount) || amount < 250 || !Number.isFinite(paidAmount) || paidAmount < amount) return notReady();
    
    const projectUrl = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if(!projectUrl||!key) return json(res,503,{error:'Private product storage is not configured.'});
    
    const storageResponse = await fetch(projectUrl.replace(/\/$/,'')+'/storage/v1/object/sign/bizkipe-products/bizkipe-premium-template-pack.zip', {
      method: 'POST', headers: { apikey: key, Authorization: 'Bearer '+key, 'Content-Type':'application/json' },
      body: JSON.stringify({ expiresIn: 300, download: 'bizkipe-premium-template-pack.zip' })
    });
    const storageData = await storageResponse.json();
    if(!storageResponse.ok || !storageData.signedURL){
      console.error('Supabase Storage signed URL error:', storageData.message || storageData.error || 'unknown');
      return json(res,503,{error:'The download file is not available yet. The site owner must upload the product pack to private storage.'});
    }
    const signed = storageData.signedURL.startsWith('http') ? storageData.signedURL : projectUrl.replace(/\/$/,'')+'/storage/v1'+(storageData.signedURL.startsWith('/')?storageData.signedURL:'/'+storageData.signedURL);
    res.statusCode = 302;
    res.setHeader('Location', signed);
    res.setHeader('Cache-Control', 'private, no-store');
    return res.end();
  } catch(error){
    console.error('download error:', error.message);
    return json(res,503,{error:'Could not prepare download.'});
  }
};
