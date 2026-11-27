const { json, adminGuard, supabase } = require('../_lib');

const ymd = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Nairobi', year: 'numeric', month: '2-digit', day: '2-digit' });
const PAID = new Set(['paid', 'fulfilled']);
const LOST = new Set(['failed', 'cancelled', 'expired']);

module.exports = async function handler(req, res) {
  if (!(await adminGuard(req, res))) return;
  if (req.method !== 'GET') return json(res, 405, { error: 'Method not allowed' });
  try {
    const rows = await supabase('orders?select=created_at,status,amount,paid_amount,currency,product_name&order=created_at.desc&limit=5000', { method: 'GET' }) || [];
    const today = ymd.format(new Date()), month = today.slice(0, 7);
    const revenue = {}, months = {}, products = {};
    let paid = 0, lost = 0, pending = 0, verify = 0;
    const cur = (c) => String(c || 'KES');
    const slot = (obj, key) => (obj[key] = obj[key] || {});
    rows.forEach((o) => {
      if (PAID.has(o.status)) {
        paid++;
        const c = cur(o.currency), amt = Number(o.paid_amount != null ? o.paid_amount : o.amount) || 0, day = ymd.format(new Date(o.created_at));
        const r = slot(revenue, c); r.all = (r.all || 0) + amt; r.paid_orders = (r.paid_orders || 0) + 1;
        if (day === today) r.today = (r.today || 0) + amt;
        if (day.slice(0, 7) === month) r.month = (r.month || 0) + amt;
        const m = slot(months, day.slice(0, 7)); const mc = slot(m, c); mc.revenue = (mc.revenue || 0) + amt; mc.orders = (mc.orders || 0) + 1;
        const pk = String(o.product_name || 'Other').slice(0, 80); const p = slot(products, pk); p[c] = (p[c] || 0) + amt; p.orders = (p.orders || 0) + 1;
      } else if (LOST.has(o.status)) lost++;
      else if (o.status === 'pending_verification') verify++;
      else if (o.status === 'pending') pending++;
    });
    const monthList = Object.keys(months).sort().reverse().slice(0, 6).map((k) => ({ month: k, by_currency: months[k] }));
    const productList = Object.entries(products).map(([name, v]) => ({ name, orders: v.orders, by_currency: Object.fromEntries(Object.entries(v).filter(([k]) => k !== 'orders')) }))
      .sort((a, b) => b.orders - a.orders).slice(0, 5);
    const attempts = paid + lost;
    return json(res, 200, {
      revenue, paid_orders: paid, failed_orders: lost, pending_orders: pending, awaiting_verification: verify,
      failure_rate: attempts ? Math.round((lost / attempts) * 100) : 0, months: monthList, products: productList, truncated: rows.length >= 5000
    });
  } catch (error) {
    console.error('admin summary error:', error.message);
    return json(res, 503, { error: 'Could not load sales numbers.' });
  }
};
