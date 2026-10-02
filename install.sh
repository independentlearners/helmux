#!/usr/bin/env bash
#
# install.sh — Pasang Helix (hx) portable secara global di Termux + uji hasilnya.
#
# Cara pakai (dari dalam folder hasil ekstrak zip):
#   cd helix-portable
#   bash install.sh
#
# Struktur paket yang diharapkan (sejajar dengan script ini):
#   ./hx
#   ./runtime/{grammars,queries,themes,tutor}
#
# Script ini idempotent — aman dijalankan ulang untuk update/reinstall.

set -u

OK="✓"; BAD="✗"; INF="ℹ"
PASS_COUNT=0
FAIL_COUNT=0

pass() { printf "  \033[32m%s\033[0m %s\n" "$OK" "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf "  \033[31m%s\033[0m %s\n" "$BAD" "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
info() { printf "  \033[36m%s\033[0m %s\n" "$INF" "$1"; }
step() { printf "\n\033[1m%s\033[0m\n" "$1"; }
abort() { printf "\n\033[31mGagal:\033[0m %s\n" "$1"; exit 1; }

# ---------- 0. Prasyarat ----------
step "0. Memeriksa lingkungan"

[ -n "${PREFIX:-}" ] || abort "\$PREFIX kosong — script ini harus dijalankan di dalam Termux."
pass "Berjalan di dalam Termux (\$PREFIX = $PREFIX)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_HX="$SCRIPT_DIR/hx"
SRC_RUNTIME="$SCRIPT_DIR/runtime"

[ -f "$SRC_HX" ] || abort "Tidak ditemukan '$SRC_HX'. Jalankan script dari dalam folder hasil ekstrak zip."
[ -d "$SRC_RUNTIME" ] || abort "Tidak ditemukan folder '$SRC_RUNTIME'. Paket zip kemungkinan tidak lengkap."
pass "Sumber ditemukan: hx + runtime/"

if command -v file >/dev/null 2>&1; then
    if file "$SRC_HX" | grep -qi 'ELF'; then
        pass "Binary hx valid (ELF)"
    else
        abort "'$SRC_HX' bukan binary ELF (kemungkinan wrapper/script lama atau file korup)."
    fi
else
    info "Perintah 'file' tidak ada — lewati cek ELF (opsional: pkg install file)"
fi

# ---------- 1. Instalasi ke lokasi global ----------
step "1. Memasang ke \$PREFIX/opt/helix"

DEST="$PREFIX/opt/helix"

if [ -e "$PREFIX/bin/hx" ] && [ ! -L "$PREFIX/bin/hx" ]; then
    info "\$PREFIX/bin/hx sudah ada sebagai file asli (bukan symlink)."
    info "Kemungkinan dari 'pkg install helix' resmi — akan ditimpa dalam 3 detik (Ctrl+C untuk batal)."
    sleep 3
fi

mkdir -p "$DEST" || abort "Gagal membuat $DEST"
rm -rf "$DEST/runtime"   # hindari runtime lama ter-nesting di dalam runtime baru

cp "$SRC_HX" "$DEST/hx"            && pass "Binary disalin ke $DEST/hx"       || abort "Gagal menyalin binary"
cp -r "$SRC_RUNTIME" "$DEST/runtime" && pass "Runtime disalin ke $DEST/runtime" || abort "Gagal menyalin runtime"
chmod +x "$DEST/hx"                && pass "Permission eksekusi diset"         || abort "Gagal chmod +x"
ln -sf "$DEST/hx" "$PREFIX/bin/hx" && pass "Symlink: \$PREFIX/bin/hx -> $DEST/hx" || abort "Gagal membuat symlink"

# ---------- 2. Cek konflik PATH ----------
step "2. Memeriksa PATH di sesi ini"

RESOLVED_HX="$(command -v hx 2>/dev/null || true)"
if [ "$RESOLVED_HX" = "$PREFIX/bin/hx" ]; then
    pass "'hx' pada PATH sesi ini sudah menunjuk ke $PREFIX/bin/hx"
elif [ -n "$RESOLVED_HX" ]; then
    fail "'hx' pada PATH sesi ini masih menunjuk ke: $RESOLVED_HX"
    info "Cek baris lama di: ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc"
else
    info "Belum bisa dites di sesi ini (normal pada instalasi pertama kali)"
fi
info "Alias tidak ikut terdeteksi dari script (aliases tidak diwariskan ke child process)."
info "Cek manual di shell interaktifmu: alias hx"

# ---------- 3. Pengujian hasil instalasi ----------
step "3. Pengujian (memanggil langsung $DEST/hx, independen dari PATH)"

VERSION_OUT="$("$DEST/hx" --version 2>&1)"
if echo "$VERSION_OUT" | grep -qi 'helix'; then
    pass "hx --version -> $VERSION_OUT"
else
    fail "hx --version tidak sesuai harapan: $VERSION_OUT"
fi

HEALTH_OUT="$("$DEST/hx" --health 2>&1)"
if echo "$HEALTH_OUT" | grep -q "$DEST/runtime"; then
    if echo "$HEALTH_OUT" | grep "$DEST/runtime" | grep -qi "does not exist"; then
        fail "Runtime $DEST/runtime terdaftar tapi ditandai tidak ada"
    else
        pass "Runtime $DEST/runtime terdeteksi dan valid"
    fi
else
    fail "Runtime $DEST/runtime tidak muncul di 'hx --health'"
fi

for item in grammars queries themes; do
    if [ -d "$DEST/runtime/$item" ] && [ -n "$(ls -A "$DEST/runtime/$item" 2>/dev/null)" ]; then
        pass "runtime/$item berisi data"
    else
        fail "runtime/$item kosong atau tidak ada"
    fi
done

# tutor adalah sebuah FILE di struktur resmi Helix, bukan direktori
if [ -f "$DEST/runtime/tutor" ] && [ -s "$DEST/runtime/tutor" ]; then
    pass "runtime/tutor ada dan berisi data"
else
    fail "runtime/tutor kosong atau tidak ada"
fi

CLEAN_VERSION="$(env -i HOME="$HOME" PREFIX="$PREFIX" PATH="$PREFIX/bin" "$PREFIX/bin/hx" --version 2>&1)"
if echo "$CLEAN_VERSION" | grep -qi 'helix'; then
    pass "Jalan dari environment bersih total (PATH=\$PREFIX/bin saja) -> global sejati"
else
    fail "Gagal di environment bersih: $CLEAN_VERSION"
fi

# ---------- 4. Info opsional: language server ----------
step "4. Language server (opsional, tidak memengaruhi status instalasi inti)"

check_optional() {
    if command -v "$1" >/dev/null 2>&1; then
        info "$1 terpasang ($(command -v "$1"))"
    else
        info "$1 belum terpasang — pasang dengan: $2"
    fi
}
check_optional bash-language-server "pkg install nodejs && npm install -g bash-language-server"
check_optional lua-language-server  "pkg install lua-language-server"
check_optional dart                 "pkg install dart"

# ---------- Ringkasan ----------
step "Ringkasan"
printf "  Lulus : \033[32m%s\033[0m\n" "$PASS_COUNT"
printf "  Gagal : \033[31m%s\033[0m\n" "$FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
    printf "\n\033[32mInstalasi global berhasil.\033[0m\n"
    printf "Kalau bagian '2. Memeriksa PATH' di atas gagal, sesi shell ini masih menyimpan cache lokasi lama.\n"
    printf "Jalankan salah satu: 'hash -r' (bash) / 'rehash' (zsh), atau buka sesi baru, lalu cek ulang: hx --health\n"
    exit 0
else
    printf "\n\033[31mAda %s pengujian gagal.\033[0m Tinjau pesan di atas sebelum dianggap selesai.\n" "$FAIL_COUNT"
    exit 1
fi
