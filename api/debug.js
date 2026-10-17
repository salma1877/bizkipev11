export default function handler(req, res) {
  const checks = {
    MPESA_ENV: !!process.env.MPESA_ENV,
    MPESA_CONSUMER_KEY: !!process.env.MPESA_CONSUMER_KEY,
    MPESA_CONSUMER_SECRET: !!process.env.MPESA_CONSUMER_SECRET,
    MPESA_PASSKEY: !!process.env.MPESA_PASSKEY,
    MPESA_SHORTCODE: !!process.env.MPESA_SHORTCODE,
    MPESA_STORE_NUMBER: !!process.env.MPESA_STORE_NUMBER,
    MPESA_CALLBACK_URL: !!process.env.MPESA_CALLBACK_URL,
    SUPABASE_URL: !!process.env.SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_URL: !!process.env.NEXT_PUBLIC_SUPABASE_URL,
    SUPABASE_SERVICE_ROLE_KEY: !!process.env.SUPABASE_SERVICE_ROLE_KEY,
    SUPABASE_ANON_KEY: !!process.env.SUPABASE_ANON_KEY,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  };
  res.json({checks, all_mpesa_ok: checks.MPESA_ENV && checks.MPESA_CONSUMER_KEY && checks.MPESA_CONSUMER_SECRET && checks.MPESA_PASSKEY});
}
