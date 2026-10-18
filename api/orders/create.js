export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const body = req.body;
    console.log('CREATE BODY:', JSON.stringify(body).slice(0,1500));
    
    const PRODUCTS = {
      'premium-template-pack': { name: 'Premium Template Pack', amount: 250, currency: 'KES' },
      'bizkipe_templates': { name: 'BizKipe Templates', amount: 150, currency: 'KES' },
      'templates': { name: 'BizKipe Templates', amount: 150, currency: 'KES' },
      'emerald-business': { name: 'Emerald Business', amount: 250, currency: 'KES' },
      'warm-minimal': { name: 'Warm Minimal', amount: 150, currency: 'KES' },
    };

    let productId = body.productId || 'premium-template-pack';
    let product = PRODUCTS[productId];
    
    if (!product) {
      console.log('Unknown productId', productId, 'using fallback 150');
      product = { name: productId, amount: 150, currency: 'KES' };
      // If it's emerald, charge 250
      if (productId.includes('emerald') || productId.includes('premium')) {
        product.amount = 250;
      }
    }

    return res.status(200).json({ 
      orderId: 'order_' + Date.now(),
      product,
      amount: product.amount
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
}
