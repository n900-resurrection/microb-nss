# microb-nss: NSPR/NSS with TLS 1.2 as a replacement of the libraries of MicroB. Targets and conventions: ../../mk/app.mk
override APP     := microb-nss
VERSION ?= 3.28.6
REV     ?= 1maemo2
include ../../mk/app.mk
