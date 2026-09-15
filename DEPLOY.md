# Panduan Deploy dengan Coolify

Dokumen ini menjelaskan cara men-build dan menghosting **frontend Hero Ingredient** (situs Astro statis) di Coolify memakai Dockerfile yang ada di repo ini.

> **Catatan:** repo ini HANYA berisi frontend. Backend Express (produk, checkout, Midtrans, login) ada di repo terpisah dan di-deploy sebagai aplikasi Coolify tersendiri. Frontend berbicara ke backend lewat variabel `PUBLIC_API_BASE`.

---

## 1. Bagaimana image ini dibangun

`Dockerfile` punya dua tahap:

| Tahap | Isi | Hasil |
| --- | --- | --- |
| `build` (node:22-alpine) | `npm ci` lalu `npm run build` | Folder `dist/` berisi HTML/CSS/JS statis |
| `runtime` (nginx:alpine) | Salin `dist/` + `nginx.conf` | Situs siap dilayani di **port 80** |

Image akhir **tidak berisi Node.js maupun kode sumber** — hanya Nginx + berkas hasil build, sehingga ringan dan permukaan serangannya kecil.

Fungsi `nginx.conf`:

- `try_files $uri $uri/ $uri.html` → URL bersih seperti `/about` dilayani dari `/about/index.html` (Astro mem-build tiap halaman sebagai folder).
- `/_astro/` di-cache 1 tahun (nama berkasnya sudah mengandung hash), aset `public/` di-cache 7 hari, HTML selalu divalidasi ulang.
- Endpoint `GET /healthz` untuk health check.
- Kompresi gzip + header keamanan dasar.

---

## 2. Konsep paling penting: variabel `PUBLIC_*` bersifat BUILD-TIME

Ini penyebab kesalahan paling umum saat deploy Astro.

Astro **membekukan** (menyisipkan langsung) nilai variabel berawalan `PUBLIC_` ke dalam HTML/JS **pada saat `npm run build` dijalankan**. Variabel ini **bukan** dibaca saat container berjalan.

Akibatnya:

- Mengubah `PUBLIC_API_BASE` di Coolify **tidak** langsung berpengaruh.
- Anda **wajib build ulang** (Redeploy) setiap kali nilai salah satu variabel `PUBLIC_*` berubah.
- Karena itu, di Coolify variabel ini harus ditandai sebagai **Build Variable**, bukan sekadar runtime variable.

Variabel yang wajib ada saat build:

| Variabel | Contoh nilai | Keterangan |
| --- | --- | --- |
| `PUBLIC_API_BASE` | `https://api.heroingredient.com` | URL backend Express. Tanpa garis miring di akhir. Kosongkan bila backend berada di domain yang sama. |
| `PUBLIC_MIDTRANS_CLIENT_KEY` | `Mid-client-xxxxxxxx` | Client key Midtrans (aman tampil di browser). |
| `PUBLIC_MIDTRANS_IS_PRODUCTION` | `true` atau `false` | `true` = mode produksi Midtrans, `false` = sandbox. |
| `PUBLIC_GOOGLE_CLIENT_ID` | `1234567890-abc.apps.googleusercontent.com` | Untuk tombol "Masuk dengan Google". Kosongkan bila tidak dipakai. |

> File `.env` lokal **sengaja dikecualikan** lewat `.dockerignore`, jadi rahasia lokal tidak pernah ikut ke dalam image. Nilai produksi hanya berasal dari Build Variables di Coolify.

---

## 3. Langkah deploy di Coolify

### 3.1 Persiapkan repo

1. Pastikan semua perubahan sudah di-commit dan di-push ke GitHub (`git push`).
2. Pastikan `Dockerfile` dan `nginx.conf` ikut ter-push — keduanya wajib ada.

### 3.2 Buat aplikasi baru

1. Buka dashboard Coolify.
2. Klik **+ New** (kiri atas) → pilih **Resource**.
3. Pilih sumber repo:
   - **Public Repository** — isi URL repo GitHub, mis. `https://github.com/<user>/heroingredient.com`.
   - **Private Repository (GitHub App)** — sambungkan GitHub App lebih dulu bila repo privat.
4. Pada bagian **Build Pack**, pilih **Dockerfile**.
5. Isi kolom berikut:
   - **Base Directory**: `/` (biarkan kosong/ default)
   - **Dockerfile Location**: `/Dockerfile`
6. Klik **Save**.

### 3.3 Set port dan health check

1. Buka tab **Configuration** → **General**.
2. **Ports Exposes**: `80` — ini port Nginx di dalam container.
3. Buka **Health Checks**, lalu set:
   - **Health Check Path**: `/healthz`
   - **Port**: `80`
4. Klik **Save**.

### 3.4 Isi variabel `PUBLIC_*` sebagai Build Variable

1. Buka tab **Environment Variables**.
2. Klik **+ Add** untuk tiap variabel di tabel bagian 2 di atas.
3. **Penting:** aktifkan tombol/toggle **Build Variable?** pada setiap variabel `PUBLIC_*`.
4. Isi nilainya, lalu **Save**.

Contoh untuk backend yang sudah online:

```env
PUBLIC_API_BASE=https://api.heroingredient.com
PUBLIC_MIDTRANS_CLIENT_KEY=Mid-client-xxxxxxxxxxxx
PUBLIC_MIDTRANS_IS_PRODUCTION=true
PUBLIC_GOOGLE_CLIENT_ID=1234567890-abc.apps.googleusercontent.com
```

### 3.5 Pasang domain

1. Buka tab **Domains**.
2. Isi domain, mis. `https://heroingredient.com`.
3. Klik **Save**, lalu **Deploy** di pojok kanan atas.
4. Aktifkan **HTTPS** (Let's Encrypt) dari panel yang sama bila belum menyala otomatis.

### 3.6 Deploy

Klik **Deploy**. Coolify akan menjalankan build (bisa beberapa menit karena `npm ci` + `astro build`). Pantau lewat tab **Logs** / **Deployments**. Bila selesai dan container sehat, status aplikasi menjadi **Running (healthy)**.

---

## 4. Checklist sebelum go-live

- [ ] Aplikasi **backend Indonesia Ingredient** sudah ter-deploy dan endpoint `GET /api/products` merespons JSON.
- [ ] `PUBLIC_API_BASE` menunjuk ke URL backend tersebut (HTTPS, tanpa `/` di akhir).
- [ ] `PUBLIC_MIDTRANS_IS_PRODUCTION` sama dengan `MIDTRANS_IS_PRODUCTION` di backend.
- [ ] `PUBLIC_MIDTRANS_CLIENT_KEY` sesuai mode akun Midtrans yang dipakai backend.
- [ ] `PUBLIC_GOOGLE_CLIENT_ID` sama dengan `GOOGLE_CLIENT_ID` di backend (atau keduanya dikosongkan).
- [ ] Domain frontend sudah ditambahkan pada **Authorized JavaScript origins** bila login Google dipakai.
- [ ] Backend mengizinkan CORS dari domain frontend.
- [ ] Domain frontend sudah diarahkan (DNS) ke server Coolify.
- [ ] Sudah diuji: katalog tampil dari database, login berhasil, checkout menghasilkan Snap token.

---

## 5. Menyambung ke backend Indonesia Ingredient

Frontend ini **tidak punya database sendiri**. Seluruh data (katalog, pelanggan, pesanan, voucher, ongkir, pesan kontak) berasal dari backend Express + MySQL milik proyek **Indonesia Ingredient**, yang di-deploy sebagai aplikasi Coolify terpisah.

Frontend hanya butuh URL backend itu di `PUBLIC_API_BASE`. Bila backend mati atau URL-nya salah, katalog otomatis jatuh ke data cadangan statis di `src/data/products.ts` (hanya berisi Turmeric), dan login/checkout/kontak tidak berfungsi.

### 5.1 Yang harus disamakan antara frontend dan backend

Ketiganya **wajib konsisten** — kalau tidak, fitur akan gagal tanpa pesan yang jelas:

| Di frontend ini | Harus sama dengan | Akibat bila beda |
| --- | --- | --- |
| `PUBLIC_MIDTRANS_IS_PRODUCTION` | `MIDTRANS_IS_PRODUCTION` di `Backend/.env` | Snap gagal terbuka / token ditolak |
| `PUBLIC_MIDTRANS_CLIENT_KEY` | `MIDTRANS_SERVER_KEY` di `Backend/.env` | Pembayaran gagal (client key sandbox ≠ server key produksi) |
| `PUBLIC_GOOGLE_CLIENT_ID` | `GOOGLE_CLIENT_ID` di `Backend/.env` | Login Google gagal; backend menolak `id_token` |

Catatan: bila `GOOGLE_CLIENT_ID` **kosong di backend**, biarkan `PUBLIC_GOOGLE_CLIENT_ID` juga kosong. Mengisinya di frontend saja justru akan memunculkan tombol Google yang selalu gagal.

### 5.2 CORS

Backend saat ini memakai `app.use(cors())` — semua origin diizinkan. Ini membuat penyambungan berhasil tanpa konfigurasi tambahan, **tetapi sebaiknya dikunci** ke domain resmi sebelum go-live dengan mengganti menjadi:

```js
app.use(cors({ origin: 'https://heroingredient.com' }));
```

Setelah dikunci, tambahkan juga origin domain staging/preview bila ada.

### 5.3 Menguji sambungan sebelum deploy

Jalankan backend secara lokal, lalu pastikan endpointnya hidup:

```powershell
npm --prefix ..\indonesiaingredient.com\Backend start
Invoke-WebRequest http://localhost:5000/api/products -UseBasicParsing
```

Lalu buka `http://localhost:4321/products` — katalog harus menampilkan produk dari database (bukan hanya Turmeric).


---

## 6. Troubleshooting

**Build gagal di tahap `npm ci`**
`package-lock.json` tidak sinkron dengan `package.json`. Jalankan `npm install` lokal, commit `package-lock.json`, lalu push dan deploy ulang.

**Halaman selain `/` menghasilkan 404**
Biasanya karena aset `dist/` tidak tersalin atau `nginx.conf` tidak ikut ter-copy. Pastikan `nginx.conf` ada di root repo dan **tidak** tercantum di `.dockerignore`.

**Perubahan variabel `PUBLIC_*` tidak muncul di situs**
Ingat sifat build-time: nilai lama masih ter-beku di dalam image. Buka **Environment Variables**, pastikan toggle **Build Variable?** aktif, lalu **Redeploy** (build ulang, bukan sekadar restart).

**Tombol "Masuk dengan Google" tidak muncul**
`PUBLIC_GOOGLE_CLIENT_ID` kosong atau tidak ikut saat build. Isi lalu redeploy.

**Pembayaran Midtrans gagal / Snap tidak terbuka**
Periksa pasangan `PUBLIC_MIDTRANS_CLIENT_KEY` dan `PUBLIC_MIDTRANS_IS_PRODUCTION`. Client key sandbox tidak akan bekerja di mode produksi, dan sebaliknya.

**Container dinyatakan unhealthy**
Pastikan **Ports Exposes** = `80` dan **Health Check Path** = `/healthz`.

**Katalog hanya menampilkan Turmeric**
Backend tidak terjangkau, sehingga frontend memakai data cadangan statis. Periksa `PUBLIC_API_BASE` (harus URL produksi, bukan `http://localhost:5000`) dan pastikan aplikasi backend berstatus running. Ingat, memperbaiki nilainya butuh **Redeploy**, bukan sekadar restart.

**Halaman login/checkout error atau tombol Google selalu gagal**
Cek konsistensi tabel pada bagian 5.1 — terutama pasangan Midtrans dan Google antara frontend dan backend.
