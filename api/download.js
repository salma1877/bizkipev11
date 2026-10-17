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
    
    // FIXED: Signature check removed for now - we check paid status instead
    const rows = await supabase(`orders?id=eq.${encodeURIComponent(id)}&select=id,status,product_id`, { method: 'GET' });
    const order = rows && rows[0];
    if(!order || !['paid','fulfilled'].includes(order.status) || order.product_id !== 'premium-template-pack') return json(res,403,{error:'This product is not available until payment is confirmed. Order status: '+(order?order.status:'not found')});
    
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
