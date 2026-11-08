#!/bin/bash
# Package microb-nss as a .deb for Maemo 5: NSPR 4.16 + NSS 3.28.6 (TLS 1.2) that replace the libraries of MicroB in /usr/lib/microb-engine.
#   make debs APP=microb-nss     (not built by plain `make debs`, see MANUAL in the Makefile)
# The stock libraries are not deleted: dpkg-divert moves them to /opt/microb-nss/orig, and the package removal moves them back.
set -euo pipefail
PROJ=/project
. "$PROJ/scripts/debpack.sh"

PKG=microb-nss
VERSION="${VERSION:-3.28.6}"
OUT="$PROJ/build/out/microb-nss-$VERSION"
STAGE="$PROJ/build/deb/stage-$PKG"
HERE="$PROJ/apps/microb-nss"
[ -x "$OUT/root/opt/microb-nss/bin/psm-sim" ] || { echo "Missing build output in $OUT, run build.sh first (make build)"; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE/DEBIAN"
cp -a "$OUT/root/." "$STAGE/"
mkdir -p "$STAGE/opt/microb-nss/share"
install -m 644 "$HERE/README.md" "$STAGE/opt/microb-nss/share/README.md"
cp -a "$HERE/patches" "$STAGE/opt/microb-nss/share/patches"

# libraries that exist in /usr/lib/microb-engine (diverted) and new ones (only linked)
REPLACE="libnspr4 libplc4 libplds4 libnss3 libnssutil3 libsmime3 libssl3 libsoftokn3 libfreebl3 libnssdbm3"
NEWONLY="libfreeblpriv3 libnsssqlite3"

cat > "$STAGE/DEBIAN/postinst" <<EOT
#!/bin/sh
# Replace the libraries of MicroB by the TLS 1.2 ones (symbolic links into /opt/microb-nss/lib); the running browserd keeps its old libraries until it is restarted.
[ "\$1" = configure ] || exit 0
L=/opt/microb-nss/lib; E=/usr/lib/microb-engine; O=/opt/microb-nss/orig
[ -d \$E ] || { echo "microb-nss: \$E not found, nothing replaced"; exit 0; }
# the new libraries must load (psm-sim prints its usage and exits with 2 when they do)
LD_LIBRARY_PATH=\$L /opt/microb-nss/bin/psm-sim >/dev/null 2>&1; rc=\$?
[ \$rc -eq 2 ] || { echo "microb-nss: the new libraries do not load (exit \$rc), nothing replaced"; exit 1; }
mkdir -p \$O
for l in $REPLACE; do
    if [ "\$(dpkg-divert --listpackage \$E/\$l.so)" != microb-nss ]; then
        dpkg-divert --package microb-nss --quiet --rename --divert \$O/\$l.so --add \$E/\$l.so || exit 1
    fi
    ln -sf \$L/\$l.so \$E/\$l.so
done
for l in $NEWONLY; do ln -sf \$L/\$l.so \$E/\$l.so; done
ldconfig 2>/dev/null
echo "microb-nss: installed. Restart the browser daemon to use it: /etc/init.d/tablet-browser-daemon.init restart (or reboot)."
exit 0
EOT

cat > "$STAGE/DEBIAN/prerm" <<EOT
#!/bin/sh
# Put the stock libraries of MicroB back (only the links of this package are removed, and the diversion gives the originals back).
case "\$1" in remove|purge) ;; *) exit 0 ;; esac
E=/usr/lib/microb-engine
for l in $NEWONLY; do
    [ -L \$E/\$l.so ] && rm -f \$E/\$l.so
done
for l in $REPLACE; do
    if [ "\$(dpkg-divert --listpackage \$E/\$l.so)" = microb-nss ]; then
        [ -L \$E/\$l.so ] && rm -f \$E/\$l.so
        dpkg-divert --package microb-nss --quiet --rename --remove \$E/\$l.so
    fi
done
ldconfig 2>/dev/null
echo "microb-nss: the stock libraries are back. Restart the browser daemon: /etc/init.d/tablet-browser-daemon.init restart (or reboot)."
exit 0
EOT
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm"

SECTION=user/network
DEPENDS="libnss3, libnspr4"
DISPLAY_NAME="microb-nss"
SHORT_DESC="NSS 3.28 with TLS 1.2 for the MicroB browser"
LONG_DESC="Replaces NSPR 4.8 / NSS 3.12 of the MicroB engine by NSPR 4.16 / NSS 3.28.6 (TLS 1.2, AES-GCM, ChaCha20, SSL 3.0 off), so that sites that dropped TLS 1.0 open in the stock browser. The stock libraries are kept in /opt/microb-nss/orig (dpkg-divert) and come back when the package is removed. Restart the browser daemon after installing or removing: /etc/init.d/tablet-browser-daemon.init restart.
Tool: /opt/microb-nss/bin/psm-sim host port (a TLS test that sets NSS up as MicroB does, run it with LD_LIBRARY_PATH=/opt/microb-nss/lib)."
debpack_build
