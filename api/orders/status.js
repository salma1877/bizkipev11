export default async function handler(req, res){
  function json(r,c,o){ r.statusCode=c; r.setHeader('Content-Type','application/json'); r.setHeader('Cache-Control','no-store'); r.end(JSON.stringify(o)); }
  async function sha256(text){
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf)).map(b=>b.toString(16).padStart(2,'0')).join('');
  }
  try{
    const id = String(req.query.orderId || req.query.order_id || req.query.id || '');
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) return json(res,400,{error:'Missing or invalid order id', status:'pending'});
    const supplied = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
    if(!supplied) return json(res,401,{error:'Order access token required.', status:'pending'});
    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if(!url||!key) return json(res,503,{error:'Order status is not available right now.', status:'pending'});
    const r = await fetch(url.replace(/\/$/,'')+'/rest/v1/orders?id=eq.'+encodeURIComponent(id)+'&select=id,status,product_id,access_token_hash', {
      headers: { apikey: key, Authorization: 'Bearer '+key }
    });
    const rows = await r.json();
    const order = Array.isArray(rows) ? rows[0] : null;
    const same = order && (await sha256(supplied)) === order.access_token_hash;
    if(!same) return json(res,404,{error:'Invalid order reference.', status:'pending'});
    const out = { status: order.status, id: order.id, product_id: order.product_id };
    if(['paid','fulfilled'].includes(order.status) && order.product_id === 'premium-template-pack') out.downloadUrl = '/api/download?orderId='+encodeURIComponent(order.id);
    return json(res,200,out);
  }catch(e){
    console.error(e.message);
    return json(res,500,{error:'Server error', status:'pending'});
  }
}
