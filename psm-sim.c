/* psm-sim: imitates how the Gecko 1.9.2 of MicroB (PSM, security/manager/ssl/src/nsNSSComponent.cpp) sets up NSS, then makes one TLS connection
 * and prints the negotiated protocol version and cipher suite. It is the test of the patches of apps/microb-nss: PSM switches off every suite of the
 * library and enables only its own list of old suites (CBC with SHA-1), and enables SSL 3.0 and TLS with the old option calls.
 *   psm-sim host port [ip]  (host is the name for SNI; ip skips the DNS lookup; no certificate check: this is a protocol test, not a browser)
 * Exit code 0 when the handshake worked. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <nspr.h>
#include <nss.h>
#include <ssl.h>
#include <sslproto.h>
#include <sslerr.h>
#include <secerr.h>

static SECStatus accept_any(void *arg, PRFileDesc *fd, PRBool checksig, PRBool isServer)
{
    return SECSuccess;
}

static const char *vname(int v)
{
    switch (v) {
    case 0x0300: return "SSL 3.0";
    case 0x0301: return "TLS 1.0";
    case 0x0302: return "TLS 1.1";
    case 0x0303: return "TLS 1.2";
    default: return "?";
    }
}

int main(int argc, char **argv)
{
    /* the suites that PSM of MicroB enables (nsNSSComponent.cpp CipherPrefs, the CBC and RC4 ones with SHA-1) */
    static const PRUint16 psm_suites[] = {
        TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA, TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA, TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,
        TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA, TLS_DHE_RSA_WITH_AES_256_CBC_SHA, TLS_DHE_RSA_WITH_AES_128_CBC_SHA,
        TLS_RSA_WITH_AES_256_CBC_SHA, TLS_RSA_WITH_AES_128_CBC_SHA, TLS_RSA_WITH_3DES_EDE_CBC_SHA, TLS_RSA_WITH_RC4_128_SHA,
    };
    PRNetAddr addr;
    PRFileDesc *tcp, *ssl;
    SSLChannelInfo ci;
    SSLCipherSuiteInfo si;
    const PRUint16 *p;
    int i;

    if (argc != 3 && argc != 4) {
        fprintf(stderr, "usage: psm-sim host port [ip]\n");
        return 2;
    }
    PR_Init(PR_USER_THREAD, PR_PRIORITY_NORMAL, 0);
    if (NSS_NoDB_Init(NULL) != SECSuccess) {
        fprintf(stderr, "NSS_NoDB_Init failed: %d\n", PR_GetError());
        return 1;
    }
    NSS_SetDomesticPolicy();

    /* as PSM: SSL 2 off, SSL 3 and TLS on (old option calls, no version ranges) */
    SSL_OptionSetDefault(SSL_ENABLE_SSL2, PR_FALSE);
    SSL_OptionSetDefault(SSL_V2_COMPATIBLE_HELLO, PR_FALSE);
    SSL_OptionSetDefault(SSL_ENABLE_SSL3, PR_TRUE);
    SSL_OptionSetDefault(SSL_ENABLE_TLS, PR_TRUE);
    /* as PSM: disable every suite of the library, then enable only the own list */
    for (i = 0; i < SSL_NumImplementedCiphers; ++i)
        SSL_CipherPrefSetDefault(SSL_ImplementedCiphers[i], PR_FALSE);
    for (p = psm_suites; p < psm_suites + sizeof psm_suites / sizeof *psm_suites; ++p)
        SSL_CipherPrefSetDefault(*p, PR_TRUE);

    if (argc == 4) {
        if (PR_StringToNetAddr(argv[3], &addr) != PR_SUCCESS) {
            fprintf(stderr, "bad address %s\n", argv[3]);
            return 1;
        }
        PR_InitializeNetAddr(PR_IpAddrNull, (PRUint16)atoi(argv[2]), &addr);
        PR_StringToNetAddr(argv[3], &addr);
        addr.inet.port = PR_htons((PRUint16)atoi(argv[2]));
    } else {
        PRAddrInfo *ai = PR_GetAddrInfoByName(argv[1], PR_AF_INET, 0);
        void *iter = NULL;
        if (!ai || PR_EnumerateAddrInfo(iter, ai, (PRUint16)atoi(argv[2]), &addr) == NULL) {
            fprintf(stderr, "cannot resolve %s\n", argv[1]);
            return 1;
        }
        PR_FreeAddrInfo(ai);
    }
    tcp = PR_OpenTCPSocket(PR_NetAddrFamily(&addr));
    if (!tcp || PR_Connect(tcp, &addr, PR_SecondsToInterval(15)) != PR_SUCCESS) {
        fprintf(stderr, "connect failed: %d\n", PR_GetError());
        return 1;
    }
    ssl = SSL_ImportFD(NULL, tcp);
    SSL_OptionSet(ssl, SSL_SECURITY, PR_TRUE);
    SSL_SetURL(ssl, argv[1]);                       /* SNI */
    SSL_AuthCertificateHook(ssl, accept_any, NULL);
    SSL_ResetHandshake(ssl, PR_FALSE);
    if (SSL_ForceHandshake(ssl) != SECSuccess) {
        fprintf(stderr, "handshake failed: error %d (%s)\n", PR_GetError(), PR_ErrorToName(PR_GetError()));
        return 1;
    }
    if (SSL_GetChannelInfo(ssl, &ci, sizeof ci) == SECSuccess && SSL_GetCipherSuiteInfo(ci.cipherSuite, &si, sizeof si) == SECSuccess)
        printf("%s %s\n", vname(ci.protocolVersion), si.cipherSuiteName);
    PR_Close(ssl);
    NSS_Shutdown();
    PR_Cleanup();
    return 0;
}
