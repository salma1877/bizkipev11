export default function sitemap() {
  const baseUrl = 'https://bizkipe.vercel.app'
  return [
    { url: baseUrl },
    { url: baseUrl + '/premium' },
    { url: baseUrl + '/about' },
  ]
}
