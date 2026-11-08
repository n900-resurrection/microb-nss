#!/bin/bash
# Cross-build NSPR 4.16 + NSS 3.28.6 (with the two patches of apps/microb-nss/patches) for Maemo 5 (armel, glibc 2.5) as a replacement of the
# libraries of MicroB (see DOC/microb.md). Run INSIDE the Workshop:  make -C apps/microb-nss build
# Output: /project/build/out/microb-nss-$VERSION/root/opt/microb-nss/{lib,bin}
set -euo pipefail

VERSION="${VERSION:-3.28.6}"
NSPR_V=4.16
PROJ=/project
SR="$PROJ/sysroot"
DL="$PROJ/build/downloads/nss"
T="nss-$VERSION-with-nspr-$NSPR_V"
SRC="$PROJ/build/src/$T"
OUT="$PROJ/build/out/microb-nss-$VERSION"
CC="$PROJ/scripts/maemo-gcc"
LOG="$OUT/logs"
HERE="$PROJ/apps/microb-nss"
SHA256=311ca1a832aa29af7b12750bc9e22648e3a426e8e8fd07b64c527d686e78975d   # nss-3.28.6-with-nspr-4.16.tar.gz

[ -d "$SR/usr/include" ] || { echo "Missing sysroot, run: make sysroot"; exit 1; }
rm -rf "$OUT"; mkdir -p "$DL" "$LOG" "$OUT/root/opt/microb-nss/lib" "$OUT/root/opt/microb-nss/bin"

f="$T.tar.gz"
[ -s "$DL/$f" ] || curl -fL --retry 3 -o "$DL/$f" "https://archive.mozilla.org/pub/security/nss/releases/NSS_${VERSION//./_}_RTM/src/$f"
echo "$SHA256  $DL/$f" | sha256sum -c - >/dev/null || { echo "sha256 mismatch of $f"; exit 1; }
rm -rf "$SRC"; mkdir -p "$SRC"; tar -C "$SRC" -xzf "$DL/$f"
SRC="$SRC/nss-$VERSION"
for p in "$HERE"/patches/*.patch; do ( cd "$SRC" && patch -p1 -s < "$p" ); echo "patched: $(basename "$p")"; done
cp "$SRC/nss/lib/sqlite/sqlite.def" "$SRC/nss/lib/sqlite/nsssqlite.def"   # the map file is named after the library (patch 0003)

# 1. NSPR (cross compiled; the build needs a native compiler for its helper tools)
NSPR_OBJ="$OUT/nspr-obj"; NSPR_DIST="$OUT/nspr-dist"
mkdir -p "$NSPR_OBJ"
( cd "$NSPR_OBJ"
  "$SRC/nspr/configure" --build="$(gcc -dumpmachine)" --host=arm-linux-gnueabi --target=arm-linux-gnueabi --prefix="$NSPR_DIST" \
      --enable-optimize --disable-debug --with-pthreads \
      CC="$CC" CXX=false AR=arm-linux-gnueabi-ar RANLIB=arm-linux-gnueabi-ranlib HOST_CC=gcc \
      > "$LOG/nspr-configure.log" 2>&1 || { tail -30 "$LOG/nspr-configure.log"; exit 1; }
  make -j"$(nproc)" > "$LOG/nspr-build.log" 2>&1 || { grep -E 'error|Error' "$LOG/nspr-build.log" | head -20; tail -15 "$LOG/nspr-build.log"; exit 1; }
  make install >> "$LOG/nspr-build.log" 2>&1 )
echo "== NSPR built: $(ls "$NSPR_DIST/lib" | tr '\n' ' ')"

# 2. NSS. The sqlite of NSS is renamed to libnsssqlite3.so (patch 0003 + SQLITE_LIB_NAME): MicroB has its own libsqlite3.so, and both would otherwise meet in one
#    library path. libfreebl3.so is only a small loader of libfreeblpriv3.so. Native helper (nsinstall) comes from the host compiler, the libraries from the cross wrapper; the legacy dbm database
#    (cert8.db/key3.db, libnssdbm3) is kept because MicroB uses it. zlib: the one of the sysroot (the phone has libz.so.1).
cd "$SRC/nss"
# CC goes in through the environment (a command-line CC would also reach the host helper nsinstall, which takes NATIVE_CC from its Makefile);
# OS_TEST=armv7l makes coreconf choose the ARM settings instead of those of the x86_64 host.
export CC
make -j1 all \
    BUILD_OPT=1 USE_64= NSS_DISABLE_GTESTS=1 NSS_ENABLE_WERROR=0 NSS_DISABLE_LIBPKIX=1 \
    CROSS_COMPILE=1 OS_TEST=armv7l CPU_ARCH=arm OS_TARGET=Linux OS_RELEASE=2.6 NATIVE_CC=gcc NATIVE_FLAGS=-O2 \
    CCC=false AR="arm-linux-gnueabi-ar cr \$@" RANLIB=arm-linux-gnueabi-ranlib \
    NSPR_INCLUDE_DIR="$NSPR_DIST/include/nspr" NSPR_LIB_DIR="$NSPR_DIST/lib" \
    USE_SYSTEM_ZLIB=1 ZLIB_LIBS=-lz SQLITE_LIB_NAME=nsssqlite3 \
    SOURCE_MD_DIR="$OUT/nss-dist" DIST="$OUT/nss-dist" \
    > "$LOG/nss-build.log" 2>&1 || { grep -E 'error|Error' "$LOG/nss-build.log" | head -20; tail -20 "$LOG/nss-build.log"; exit 1; }

echo "== NSS built"
D="$OUT/root/opt/microb-nss"
cp -a "$NSPR_DIST"/lib/lib{nspr4,plc4,plds4}.so "$D/lib/"
for l in nss3 nssutil3 smime3 ssl3 softokn3 freebl3 freeblpriv3 nssdbm3 nsssqlite3; do cp -L "$OUT/nss-dist/lib/lib$l.so" "$D/lib/"; done
for b in tstclnt certutil; do cp -L "$OUT/nss-dist/bin/$b" "$D/bin/"; done
# psm-sim: the test program that imitates the NSS setup of MicroB (PSM), see apps/microb-nss/psm-sim.c
"$CC" -O2 -Wall -o "$D/bin/psm-sim" "$HERE/psm-sim.c" -I"$NSPR_DIST/include/nspr" -I"$SRC/dist/public/nss" -L"$D/lib" \
    -lssl3 -lnss3 -lnssutil3 -lnspr4 -lplc4 -lplds4 -Wl,-rpath-link,"$D/lib"
arm-linux-gnueabi-strip --strip-unneeded "$D"/lib/*.so "$D"/bin/* 2>/dev/null || true
echo "== Check"
ls -l "$D/lib" "$D/bin"
