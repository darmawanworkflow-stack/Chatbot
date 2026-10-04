// Daftar pertanyaan survei. Ubah teks di sini sesuai kebutuhan cafe.
// type:
//   rating -> pelanggan memilih 1-5 dari daftar
//   nps    -> pelanggan membalas angka 0-10
//   text   -> jawaban bebas, boleh dilewati
const QUESTIONS = [
  { id: 'rasa', label: 'Rasa', type: 'rating', text: 'Bagaimana rasa makanan/minuman kami?' },
  { id: 'pelayanan', label: 'Pelayanan', type: 'rating', text: 'Bagaimana keramahan pelayanan staf kami?' },
  { id: 'kecepatan', label: 'Kecepatan', type: 'rating', text: 'Bagaimana kecepatan penyajian pesanan Anda?' },
  { id: 'kebersihan', label: 'Kebersihan & Suasana', type: 'rating', text: 'Bagaimana kebersihan dan suasana cafe kami?' },
  { id: 'harga', label: 'Harga', type: 'rating', text: 'Apakah harga sepadan dengan kualitas yang Anda dapatkan?' },
  {
    id: 'nps',
    label: 'Rekomendasi (NPS)',
    type: 'nps',
    text: 'Seberapa besar kemungkinan Anda merekomendasikan kami ke teman atau keluarga?',
  },
  { id: 'saran', label: 'Saran', type: 'text', text: 'Ada saran atau masukan untuk kami?' },
];

const RATING_OPTIONS = [
  { value: 5, title: '⭐⭐⭐⭐⭐', description: '5 - Sangat puas' },
  { value: 4, title: '⭐⭐⭐⭐', description: '4 - Puas' },
  { value: 3, title: '⭐⭐⭐', description: '3 - Biasa saja' },
  { value: 2, title: '⭐⭐', description: '2 - Kurang puas' },
  { value: 1, title: '⭐', description: '1 - Sangat tidak puas' },
];

module.exports = { QUESTIONS, RATING_OPTIONS };
