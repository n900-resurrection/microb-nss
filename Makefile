# microb-nss: NSPR/NSS with TLS 1.2 as a replacement of the libraries of MicroB. Targets and conventions: ../../mk/app.mk
# MANUAL: not built by `make debs` / `make repo` without APP (experimental, large and slow); `make debs APP=microb-nss` or `make -C apps/microb-nss deb` builds it.
override APP     := microb-nss
VERSION ?= 3.28.6
MANUAL := 1
include ../../mk/app.mk
