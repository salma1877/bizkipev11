export default function sitemap() {
  const baseUrl = 'https://bizkipev11.vercel.app'
  return [
    { url: baseUrl },
    { url: baseUrl + '/premium' },
    { url: baseUrl + '/about' },
  ]
}
