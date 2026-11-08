# microb-nss

NSPR 4.16 and NSS 3.28.6 with TLS 1.2 as a replacement of the libraries of **MicroB**, the stock browser of the N900 (Gecko 1.9.2 with NSS 3.12.6, TLS 1.0 only).
Analysis and plan: `DOC/microb.md`. The Gecko sources of the phone are archived in `apps/microb-engine`.

Why it works without rebuilding the engine: the engine (PSM) switches TLS and SSL 3.0 on with the old `SSL_ENABLE_*` calls, and in NSS 3.28 the default version
range is TLS 1.0 to 1.2. All 871 symbols that the engine imports from NSS/NSPR, and all 29 ELF version nodes, exist in the new libraries (`scripts/microb-nss-abi-check.sh`).

## Patches (`patches/`, applied to the unpacked source by `build.sh`)
1. `0001-ssl-keep-modern-cipher-suites.patch`: PSM first disables every cipher suite of the library and then enables only its own list (CBC with SHA-1).
   The patch ignores "off" for the TLS 1.2 suites (AES-GCM, ChaCha20-Poly1305, SHA-2 CBC), so that sites that dropped the old suites can be reached.
2. `0002-ssl-no-ssl3.patch`: SSL 3.0 cannot be switched on (POODLE). MicroB enables it and uses it as a fallback for "TLS intolerant" servers.
3. `0003-sqlite-private-name.patch`: the SQLite of NSS becomes `libnsssqlite3.so`, because MicroB has its own `libsqlite3.so` in the same directory.

## Build and package (not part of `make debs` and `make test`: `MANUAL` in the Makefile)
```
make -C apps/microb-nss build           # NSPR + NSS cross build in the Workshop, about 2 minutes (nothing is installed)
make debs APP=microb-nss                # the .deb; INSTALL=1 also installs it on the phone
make -C apps/microb-nss test            # on the phone, the package must be installed
```
`build.sh` runs without `-j` (the recursive NSS make breaks with a job server), uses the sysroot zlib and keeps the legacy dbm databases (`cert8.db`) that MicroB uses.

## Installation on the phone
The package links its libraries into `/usr/lib/microb-engine` and moves the stock ones to `/opt/microb-nss/orig` with `dpkg-divert`; removing the package puts them back.
Nothing is restarted: `/etc/init.d/tablet-browser-daemon.init restart` (or a reboot) makes the browser daemon load the new libraries. The `postinst` first checks that
the new libraries load at all (`psm-sim` without arguments prints its usage and exits with 2) and replaces nothing otherwise.

## psm-sim
`/opt/microb-nss/bin/psm-sim host port [ip]` sets NSS up the way PSM does (SSL 3 and TLS on, all suites off, then the old CBC list on) and prints the negotiated protocol and suite
(no certificate check). Run it with `LD_LIBRARY_PATH=/opt/microb-nss/lib`. Result under qemu-user with the patches, 2026-11-08: tls-v1-2.badssl.com TLS 1.2, www.google.com,
www.facebook.com and example.org TLS 1.2 with `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`, www.seznam.cz TLS 1.2 with `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`.
