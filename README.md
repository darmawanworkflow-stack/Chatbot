# Chatbot Survei Kepuasan Pelanggan Cafe (WhatsApp)

Pelanggan mengirim **`/survei`** ke nomor WhatsApp cafe. Bot lalu mengajukan 7 pertanyaan satu per satu, menyimpan jawaban ke **Google Sheets**, dan mengirim **kode diskon 2%** yang unik dan hanya bisa dipakai sekali.

```
Pelanggan : /survei
Bot       : Terima kasih sudah mau membantu Cafe Kita! 🙌 ...
Bot       : Pertanyaan 1/7 — Bagaimana rasa makanan/minuman kami?  [Pilih nilai ▾]
Pelanggan : ⭐⭐⭐⭐⭐
...
Bot       : Terima kasih atas masukan Anda! 🙏☕
            Kode diskon 2% Anda: CAFE-7K3PQX
            Berlaku sampai 11 Oktober 2026, untuk 1x transaksi.
```

## Fitur

- 7 pertanyaan: Rasa, Pelayanan, Kecepatan, Kebersihan & Suasana, Harga (pilihan ⭐1–5), Rekomendasi/NPS (angka 0–10), dan Saran (teks bebas, boleh dilewati).
- Jawaban rating dipilih dari daftar, jadi pelanggan tidak perlu mengetik. Angka yang diketik juga diterima.
- Satu nomor hanya bisa mengisi survei **sekali dalam 30 hari**. Batas ini bisa diatur.
- Kode diskon unik, contohnya `CAFE-7K3PQX`, berlaku **7 hari** (bisa diatur) dan hanya untuk **1x pakai**.
- Kasir cukup mengirim `/cek KODE` atau `/pakai KODE` ke nomor bot untuk memeriksa dan menandai kode.
- Pelanggan bisa mengetik `/batal` untuk berhenti. Survei otomatis batal jika 30 menit tidak dijawab.
- Hasil survei tercatat di Google Sheets: tab **Respon** dan tab **Kode Diskon** dibuat otomatis.

## Perintah

| Siapa | Pesan | Fungsi |
|---|---|---|
| Pelanggan | `/survei` | Mulai survei |
| Pelanggan | `/batal` | Batalkan survei yang sedang berjalan |
| Kasir/admin | `/cek CAFE-XXXXXX` | Cek apakah kode masih valid |
| Kasir/admin | `/pakai CAFE-XXXXXX` | Tandai kode sudah dipakai (setelah diskon diberikan) |

Perintah kasir hanya berfungsi dari nomor yang terdaftar di `ADMIN_NUMBERS`.

---

## Langkah pemasangan

### 1. Siapkan WhatsApp Cloud API (Meta)

1. Buat akun di [business.facebook.com](https://business.facebook.com) (Meta Business Manager), jika belum punya.
2. Buka [developers.facebook.com/apps](https://developers.facebook.com/apps), klik **Create App**, pilih tipe **Business**, lalu tambahkan produk **WhatsApp**.
3. Di menu **WhatsApp > API Setup** Anda akan mendapat:
   - **Phone number ID**, untuk diisi ke `WHATSAPP_PHONE_NUMBER_ID`
   - Nomor uji coba gratis dari Meta, yang bisa dipakai untuk mencoba sebelum memakai nomor asli.
4. Buat **access token permanen**: Business Settings > Users > **System users**, buat system user dengan peran admin, lalu **Generate token** dengan izin `whatsapp_business_messaging` dan `whatsapp_business_management`. Isi ke `WHATSAPP_TOKEN`.
   (Token sementara di halaman API Setup hanya berlaku 24 jam.)
5. Salin **App Secret** dari App Settings > Basic, lalu isi ke `WHATSAPP_APP_SECRET`.
6. Tambahkan nomor WhatsApp asli cafe di **API Setup > Add phone number**.
   > ⚠️ Nomor yang sedang dipakai di aplikasi WhatsApp/WA Business di HP biasanya harus dilepas dulu dari aplikasi. Alternatifnya, gunakan penyedia resmi (BSP) yang mendukung fitur *coexistence* agar nomor tetap bisa dipakai di HP. Kalau ragu, gunakan nomor baru khusus untuk bot.

### 2. Siapkan Google Sheets

1. Buka [console.cloud.google.com](https://console.cloud.google.com), buat project baru, lalu aktifkan **Google Sheets API**.
2. Masuk ke **IAM & Admin > Service Accounts**, buat service account, lalu di tab **Keys** pilih **Add key > JSON**. File JSON akan terunduh.
3. Buat Google Sheet baru. Klik **Share**, lalu bagikan ke email service account (`...@...iam.gserviceaccount.com`) sebagai **Editor**.
4. Salin ID sheet dari URL `https://docs.google.com/spreadsheets/d/`**`ID_INI`**`/edit`, lalu isi ke `SPREADSHEET_ID`.
5. Simpan file JSON sebagai `service-account.json` di folder project (file ini sudah diabaikan oleh git), atau tempel isinya ke `GOOGLE_SERVICE_ACCOUNT_JSON`.

### 3. Jalankan bot

Butuh **Node.js 20.6 atau lebih baru**.

```bash
npm install
cp .env.example .env     # lalu isi semua nilainya
npm run dev              # menjalankan bot di komputer sendiri (membaca file .env)
npm test                 # menjalankan test otomatis
```

Mau mencoba tanpa Google Sheets? Isi `STORAGE=memory`. Data akan hilang setiap kali server restart.

### 4. Online-kan (deploy) dan sambungkan webhook

Bot harus bisa diakses dari internet dengan HTTPS. Beberapa pilihan:

- **Render / Railway / Fly.io**: hubungkan repo GitHub ini. Isi *start command* `npm start` dan isi semua variabel dari `.env.example` di menu Environment. Pilih paket yang **tidak tidur (sleep)**, karena sesi survei disimpan di memori server.
- **VPS sendiri**: jalankan `npm start` dengan pm2 atau systemd di belakang Nginx + HTTPS.
- **Uji coba lokal**: `npx ngrok http 3000`, lalu pakai URL https dari ngrok.

Setelah online, buka **WhatsApp > Configuration > Webhook** di dashboard Meta:

- **Callback URL**: `https://alamat-bot-anda/webhook`
- **Verify token**: sama dengan `WHATSAPP_VERIFY_TOKEN`
- Klik **Verify and save**, lalu **Subscribe** ke field **messages**.

Coba kirim `/survei` ke nomor bot. 🎉

---

## Pengaturan (`.env`)

| Variabel | Default | Keterangan |
|---|---|---|
| `CAFE_NAME` | `Cafe Kami` | Nama cafe di pesan bot |
| `DISCOUNT_PERCENT` | `2` | Besar diskon (%) |
| `CODE_PREFIX` | `CAFE` | Awalan kode diskon |
| `CODE_VALID_DAYS` | `7` | Masa berlaku kode (hari) |
| `SURVEY_COOLDOWN_DAYS` | `30` | Jeda minimal antar survei per nomor (`0` = tanpa batas) |
| `ADMIN_NUMBERS` | – | Nomor kasir, format `62...`, pisahkan dengan koma |
| `TIMEZONE` | `Asia/Jakarta` | Zona waktu untuk tanggal di sheet dan pesan |

## Mengubah pertanyaan

Edit `src/questions.js`. Setiap pertanyaan punya `id`, `label` (judul kolom di sheet), `type` (`rating`, `nps`, atau `text`), dan `text`.
Kalau Anda menambah, menghapus, atau mengubah urutan pertanyaan, **hapus baris judul (baris 1) di tab Respon**, atau buat tab baru, supaya judul kolom diperbarui saat bot dijalankan ulang.

## Membaca hasil survei

Di Google Sheets, kolom D–H berisi nilai 1–5 dan kolom I berisi NPS. Contoh rumus ringkasan di tab baru:

```
Rata-rata rasa       : =AVERAGE(Respon!D:D)
Rata-rata pelayanan  : =AVERAGE(Respon!E:E)
NPS                  : =(COUNTIF(Respon!I:I,">=9")-COUNTIF(Respon!I:I,"<=6"))/COUNT(Respon!I:I)*100
```

## Biaya

- Pesan WhatsApp: karena pelanggan yang memulai chat, balasan bot dalam 24 jam termasuk *service conversation* yang **gratis** menurut kebijakan harga Meta saat ini. Bot ini tidak mengirim pesan promosi (template).
- Google Sheets: gratis.
- Hosting: tergantung penyedia, mulai dari gratis atau beberapa dolar per bulan.

## Catatan teknis

- Sesi survei yang sedang berjalan disimpan di memori. Jika server restart di tengah survei, pelanggan cukup mengetik `/survei` lagi. Jalankan hanya **satu** instance server.
- Data jawaban dan kode diskon tersimpan permanen di Google Sheets.
- Jika `WHATSAPP_APP_SECRET` diisi, setiap webhook diverifikasi tanda tangannya, sehingga hanya pesan dari Meta yang diproses.

## Struktur kode

```
src/
  index.js          titik masuk, menyusun semua komponen
  config.js         membaca variabel environment
  questions.js      daftar pertanyaan survei
  survey.js         alur percakapan, kode diskon, perintah kasir
  whatsapp.js       klien WhatsApp Cloud API + parser webhook
  server.js         server Express (webhook, verifikasi tanda tangan)
  codes.js          pembuat kode diskon
  storage/sheets.js penyimpanan Google Sheets
  storage/memory.js penyimpanan sementara (uji coba/test)
test/               test otomatis (npm test)
```
