# ============================================================
# STAGE 1 — BUILD SITUS ASTRO (output statis ke /app/dist)
# ============================================================
FROM node:22-alpine AS build
WORKDIR /app

# Variabel berawalan PUBLIC_ di Astro di-inline (hardcode) ke dalam
# HTML/JS saat proses build — bukan saat runtime. Karena itu nilainya
# harus dikirim sebagai build arg, bukan environment variable biasa.
ARG PUBLIC_API_BASE=""
ARG PUBLIC_MIDTRANS_CLIENT_KEY=""
ARG PUBLIC_MIDTRANS_IS_PRODUCTION="false"
ARG PUBLIC_GOOGLE_CLIENT_ID=""

ENV PUBLIC_API_BASE=${PUBLIC_API_BASE} \
    PUBLIC_MIDTRANS_CLIENT_KEY=${PUBLIC_MIDTRANS_CLIENT_KEY} \
    PUBLIC_MIDTRANS_IS_PRODUCTION=${PUBLIC_MIDTRANS_IS_PRODUCTION} \
    PUBLIC_GOOGLE_CLIENT_ID=${PUBLIC_GOOGLE_CLIENT_ID}

# Manfaatkan layer cache: dependensi hanya di-install ulang saat lockfile berubah.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build

# ============================================================
# STAGE 2 — SERVE HASIL BUILD DENGAN NGINX
# ============================================================
FROM nginx:alpine AS runtime

# Konfigurasi server (gzip, cache, fallback routing, /healthz).
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Hanya berkas hasil build yang ikut ke image akhir.
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

# Dipakai Coolify untuk menandai container sehat.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
