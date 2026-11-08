TEST_NAME=microb-nss
need_pkg microb-nss
E=/usr/lib/microb-engine
for l in libnss3 libssl3 libsoftokn3 libnspr4; do ok "linked-$l" sh -c "test -L $E/$l.so && test -e $E/$l.so"; done
ok sqlite-private test -L $E/libnsssqlite3.so
ok stock-kept test -e /opt/microb-nss/orig/libssl3.so
ok mozilla-sqlite-untouched sh -c "! test -L $E/libsqlite3.so"
contains diverted "microb-nss" dpkg-divert --listpackage $E/libssl3.so
contains psm-sim-usage "usage: psm-sim" sh -c 'LD_LIBRARY_PATH=/opt/microb-nss/lib /opt/microb-nss/bin/psm-sim 2>&1'
# Network tests (need Wi-Fi or mobile data): psm-sim sets NSS up as MicroB does and prints the negotiated version and suite.
net() { LD_LIBRARY_PATH=/opt/microb-nss/lib timeout 60 /opt/microb-nss/bin/psm-sim "$1" "$2" 2>&1 | tail -1; }
if net example.org 443 | grep -qE '^(TLS|SSL)'; then
    contains tls12-badssl "TLS 1.2" net tls-v1-2.badssl.com 1012
    contains tls12-gcm "GCM" net example.org 443
    contains tls12-google "TLS 1.2" net www.google.com 443
else
    skip network-tests "no network or DNS"
fi
summary
