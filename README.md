# BizKipe v1.2 — deployment and launch pack

This package improves the existing BizKipe Vercel/Supabase/Daraja starter with:
- The invoice and quotation builder and premium template checkout already in v1.1
- Basic Terms, Privacy, Refund and Support pages
- Custom 404 page
- Baseline browser security headers
- robots.txt and a sitemap placeholder
- A launch checklist that distinguishes completed code from account-owner setup

## Important: this is not yet live until you configure your own accounts
I cannot log into or configure your Vercel, Supabase or Safaricom Daraja accounts from this ZIP. You must enter your own credentials in the provider dashboards. Never send credentials, API secrets, M-Pesa PINs or one-time codes in chat.

## 1. Deploy the correct folder
1. Download and extract this ZIP.
2. Upload the *contents* of `bizkipe_v1_2` to the root of the GitHub repository connected to Vercel (not the containing folder).
3. Confirm `index.html`, `admin.html`, `api/`, `vercel.json`, and `supabase-schema.sql` are at the repository root.
4. Commit/push and let Vercel deploy. If your project uses a different framework/root directory, confirm Vercel's Root Directory is the folder containing these files.

## 2. Configure Supabase
1. Create a Supabase project.
2. Open SQL Editor and run `supabase-schema.sql`.
3. In Storage, confirm bucket `bizkipe-products` is PRIVATE.
4. Upload the separately supplied `BizKipe_Premium_Template_Pack_v2.zip` to that bucket as the exact object key `bizkipe-premium-template-pack.zip`.
5. Keep the service-role key server-side only in Vercel environment variables. Never put it in `index.html`, public JS, GitHub, or a `NEXT_PUBLIC_` variable.

## 3. Configure Vercel environment variables
Copy the names from `.env.example` into Vercel → Project → Settings → Environment Variables:
- `APP_URL` = your actual HTTPS Vercel URL, no trailing slash
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ADMIN_TOKEN` = a long, unique random secret
- `DOWNLOAD_SECRET` = a different long, unique random secret
- `DARAJA_CALLBACK_KEY` = another long random secret
- `DARAJA_ENV=sandbox`
- `DARAJA_CONSUMER_KEY`, `DARAJA_CONSUMER_SECRET`, `DARAJA_SHORTCODE`, `DARAJA_PASSKEY`
- `DARAJA_TRANSACTION_TYPE` = transaction type enabled for your Daraja shortcode

Use sandbox credentials and the shortcode/passkey documented for your own Daraja app. Do not guess production credentials. Redeploy after adding/changing environment variables.

## 4. Update support and business details
Before public launch:
- Edit `support.html` and replace `REPLACE-WITH-YOUR-REAL-SUPPORT-EMAIL` with an email you control.
- Review Terms, Privacy and Refund pages to ensure they describe what you actually do and meet your legal obligations.
- Confirm product price and exactly what is included in `index.html` and the delivered ZIP.
- Add a real domain only if you have one; otherwise use your Vercel HTTPS URL.
- Update `sitemap.xml` with the real domain, or remove it until you do.
- Do not publish unsupported claims, fake testimonials, fake security badges, or unconfigured payment methods.

## 5. Daraja checkout flow
1. A customer enters their name, email and Kenyan M-Pesa phone number.
2. The server creates an order and requests an STK Push.
3. Safaricom sends a callback to `/api/daraja/callback?key=...`.
4. Only confirmed payment should unlock the download. Ambiguous payment states should remain pending for manual reconciliation.
5. Customers can keep the checkout open while it checks status; automatic email delivery is not included.

## 6. Admin
Open `/admin.html` and enter `ADMIN_TOKEN`. Treat it like a password. Use it only on a trusted device and do not share screenshots that reveal it. Confirm manual payment against the official transaction record, not a customer screenshot alone.

## 7. Mandatory testing before live payments
Use sandbox first and test:
- valid payment accepted and confirmed
- customer cancels or times out
- incorrect phone format
- duplicate callback
- incorrect amount or mismatched checkout ID
- callback arrives late or not at all
- database/storage unavailable
- paid order can download, unpaid order cannot
- expired download URL stops working
- admin token rejected when wrong
- mobile browser, desktop browser, print/PDF output

The existing callback implementation is a conservative integration starter. Confirm STK Query response fields and payment semantics against the actual responses for your Daraja app. Do not switch to production until the entire flow has been tested and Safaricom has approved/activated your production access.

## 8. Remaining production-grade work
The starter does not yet include email receipts, automated support ticketing, persistent customer accounts, rate limiting/abuse monitoring, automated backups/alerts, a full refund console, or an independent security review. Add these before depending on the site at scale. Keep the first launch small and monitor orders manually.

## 9. Legal and safety notes
The included legal pages are starter text, not legal advice. Review them against Kenyan law and your actual business. Keep personal data limited to what is necessary and secure. Never ask a customer for their M-Pesa PIN.
