/*
 * openssl_check.c - verifies that OpenSSL headers, libraries and
 * runtime DLLs are installed and usable with the current toolchain.
 * Exit code 0 = all checks passed, 1 = at least one check failed.
 */
#include <stdio.h>
#include <string.h>

#include <openssl/opensslv.h>
#include <openssl/crypto.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/ssl.h>

#if OPENSSL_VERSION_NUMBER < 0x10100000L
#error "OpenSSL 1.1.0 or newer is required"
#endif

static int failures = 0;

static void report(const char *name, int ok)
{
    printf("[%s] %s\n", ok ? " OK " : "FAIL", name);
    if (!ok) {
        failures++;
        ERR_print_errors_fp(stderr);
    }
}

int main(void)
{
    printf("Compiled against: %s\n", OPENSSL_VERSION_TEXT);
    printf("Running with:     %s\n", OpenSSL_version(OPENSSL_VERSION));
    printf("%s\n\n", OpenSSL_version(OPENSSL_DIR));

    /* 1. Header and runtime library major versions must match
     *    (catches a wrong DLL being picked up from PATH). */
    report("header/runtime major version match",
           (OPENSSL_VERSION_NUMBER >> 28) == (OpenSSL_version_num() >> 28));

    /* 2. libcrypto works: SHA-256 of "abc" against the known test vector. */
    static const unsigned char expected[32] = {
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    };
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int md_len = 0;
    int ok = EVP_Digest("abc", 3, md, &md_len, EVP_sha256(), NULL) == 1
             && md_len == sizeof expected
             && memcmp(md, expected, sizeof expected) == 0;
    report("libcrypto: SHA-256 test vector", ok);

    /* 3. libcrypto RNG is seeded and usable. */
    unsigned char buf[32];
    report("libcrypto: RAND_bytes", RAND_bytes(buf, sizeof buf) == 1);

    /* 4. libssl works: create a TLS client context. */
    SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
    report("libssl: SSL_CTX_new(TLS_client_method())", ctx != NULL);
    SSL_CTX_free(ctx);

    printf("\n%s\n", failures == 0 ? "All checks passed."
                                   : "Some checks FAILED.");
    return failures == 0 ? 0 : 1;
}