// Halaman kebijakan privasi sederhana (diminta Meta saat app dipublikasikan).

const escapeHtml = (text) =>
  String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function privacyPage({ cafeName, contact }) {
  const name = escapeHtml(cafeName);
  const contactLine = contact
    ? `hubungi kami di <strong>${escapeHtml(contact)}</strong>`
    : 'kirim pesan ke nomor WhatsApp kami';
  return `<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Kebijakan Privasi - ${name}</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px 16px; line-height: 1.6; color: #222; background: #fff; }
  h1 { font-size: 1.6rem; } h2 { font-size: 1.15rem; margin-top: 1.6em; }
</style>
</head>
<body>
<h1>Kebijakan Privasi ${name}</h1>
<p>Halaman ini menjelaskan bagaimana ${name} mengelola data yang Anda berikan saat menggunakan layanan WhatsApp kami, termasuk survei kepuasan pelanggan dan informasi promo.</p>

<h2>Data yang kami kumpulkan</h2>
<ul>
  <li>Nomor WhatsApp dan nama profil WhatsApp Anda.</li>
  <li>Jawaban survei kepuasan (penilaian dan saran yang Anda tulis).</li>
  <li>Kode diskon yang diberikan kepada Anda dan status pemakaiannya.</li>
  <li>Pilihan Anda untuk menerima atau tidak menerima informasi promo.</li>
</ul>

<h2>Tujuan penggunaan</h2>
<ul>
  <li>Meningkatkan kualitas produk dan pelayanan kami.</li>
  <li>Memberikan dan memverifikasi kode diskon.</li>
  <li>Mengirim informasi promo, hanya jika Anda menyetujuinya.</li>
</ul>

<h2>Penyimpanan dan pembagian data</h2>
<p>Data disimpan secara aman dan hanya dapat diakses oleh pengelola ${name}. Pesan dikirim melalui WhatsApp Business Platform milik Meta. Kami tidak menjual atau membagikan data Anda kepada pihak lain untuk kepentingan mereka.</p>

<h2>Hak Anda</h2>
<ul>
  <li>Berhenti menerima promo kapan saja dengan membalas <strong>STOP</strong>.</li>
  <li>Meminta salinan atau penghapusan data Anda: ${contactLine}.</li>
</ul>

<h2>Perubahan kebijakan</h2>
<p>Kebijakan ini dapat diperbarui sewaktu-waktu. Versi terbaru selalu tersedia di halaman ini.</p>
</body>
</html>`;
}

module.exports = { privacyPage };
