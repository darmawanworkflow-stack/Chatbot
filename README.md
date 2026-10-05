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
- Hasil survei tercatat di Google Sheets: tab **Respon**, **Kode Diskon**, dan **Pelanggan Promo** dibuat otomatis.
- **Promo:** setelah menerima kode diskon, pelanggan ditanya apakah mau menerima info promo (opsional, diskon tetap diberikan apa pun jawabannya). Admin bisa mengirim promo ke semua pelanggan yang setuju.

## Perintah

| Siapa | Pesan | Fungsi |
|---|---|---|
| Pelanggan | `/survei` | Mulai survei |
| Pelanggan | `/batal` | Batalkan survei yang sedang berjalan |
| Pelanggan | `STOP` | Berhenti menerima promo |
| Pelanggan | `/langganan` | Mulai (lagi) menerima promo |
| Kasir/admin | `/cek CAFE-XXXXXX` | Cek apakah kode masih valid |
| Kasir/admin | `/pakai CAFE-XXXXXX` | Tandai kode sudah dipakai (setelah diskon diberikan) |
| Admin | `/tespromo nama_template` | Kirim promo ke nomor admin sendiri untuk dicek |
| Admin | `/promo nama_template` | Siapkan promo ke semua pelanggan yang setuju |
| Admin | `/kirim` | Konfirmasi dan kirim promo (atau `/batal`) |

Perintah kasir/admin hanya berfungsi dari nomor yang terdaftar di `ADMIN_NUMBERS`.

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

### Alternatif: VPS sendiri (Ubuntu + Nginx)

```bash
# 1. Node.js 22 + pm2
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
npm install -g pm2

# 2. Ambil kode
git clone -b <branch> https://github.com/<owner>/Chatbot.git /opt/chatbot
cd /opt/chatbot && npm install --omit=dev

# 3. Isi .env (PORT=3100, HOST=127.0.0.1, GOOGLE_APPLICATION_CREDENTIALS=/opt/chatbot/service-account.json, dst.)
cp .env.example .env && nano .env

# 4. Jalankan terus-menerus
pm2 start src/index.js --name chatbot --node-args="--env-file=.env"
pm2 save && pm2 startup

# 5. Nginx + HTTPS (lihat deploy/nginx-bot.conf)
cp deploy/nginx-bot.conf /etc/nginx/sites-available/bot   # ganti server_name
ln -s /etc/nginx/sites-available/bot /etc/nginx/sites-enabled/bot
nginx -t && systemctl reload nginx
certbot --nginx -d bot.domainanda.com
```

Update kode: `cd /opt/chatbot && git pull && npm install --omit=dev && pm2 restart chatbot`.

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
| `PROMO_TEMPLATE_LANGUAGE` | `id` | Kode bahasa template promo di Meta |
| `BROADCAST_DELAY_MS` | `200` | Jeda antar pesan saat mengirim promo |

## Mengirim promo

Pesan promo ke pelanggan yang tidak sedang chat (lebih dari 24 jam sejak pesan terakhirnya) **wajib memakai template yang disetujui Meta** dan **berbayar per pesan** (kategori *Marketing*). Bot hanya mengirim ke pelanggan dengan status **aktif** di tab *Pelanggan Promo*.

1. **Buat template** di [business.facebook.com](https://business.facebook.com) > WhatsApp Manager > **Message templates** > Create template:
   - Kategori: **Marketing**, bahasa: **Indonesian** (`id`).
   - Nama huruf kecil dan garis bawah, misalnya `menu_baru_oktober`.
   - Opsional: header **gambar**, dan `{{1}}` di isi pesan untuk nama pelanggan.
   - Tambahkan tombol *Quick reply* bertuliskan **Stop promo** agar pelanggan mudah berhenti.
   - Contoh isi: `Halo {{1}}! Menu baru Es Kopi Pandan sudah hadir di Cafe Kita ☕ Tunjukkan pesan ini untuk gratis upsize minggu ini.`
2. Tunggu status **Approved**.
3. Dari nomor admin, coba dulu:
   ```
   /tespromo menu_baru_oktober nama https://link-gambar-anda.jpg
   ```
   - Tambahkan `nama` hanya jika template memakai `{{1}}`.
   - Tambahkan link gambar (https) hanya jika template memakai header gambar.
4. Jika tampilannya sudah benar, kirim ke semua pelanggan:
   ```
   /promo menu_baru_oktober nama https://link-gambar-anda.jpg
   /kirim
   ```
   Bot akan melaporkan jumlah yang berhasil dan gagal.

Tips agar nomor tetap sehat: kirim promo **maksimal 2–4 kali sebulan**, isi yang benar-benar bermanfaat, dan jangan pernah mengirim ke nomor yang tidak setuju. Banyak blokir atau laporan dari pelanggan akan menurunkan kualitas nomor dan membatasi pengiriman.

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

- Pesan survei: karena pelanggan yang memulai chat, balasan bot dalam 24 jam **gratis** menurut kebijakan harga Meta saat ini.
- Pesan promo (template *Marketing*): **berbayar per pesan**, lihat harga terbaru untuk Indonesia di halaman *WhatsApp Business Platform Pricing* Meta.
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
  promo.js          persetujuan promo, STOP, broadcast template
  whatsapp.js       klien WhatsApp Cloud API + parser webhook
  server.js         server Express (webhook, verifikasi tanda tangan)
  codes.js          pembuat kode diskon
  storage/sheets.js penyimpanan Google Sheets
  storage/memory.js penyimpanan sementara (uji coba/test)
test/               test otomatis (npm test)
```
