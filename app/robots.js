export default function robots() {
  const baseUrl = 'https://bizkipe.vercel.app'
  return {
    rules: { userAgent: '*', allow: '/' },
    sitemap: baseUrl + '/sitemap.xml',
  }
}
