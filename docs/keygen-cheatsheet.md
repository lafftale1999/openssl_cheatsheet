# Key Generation Cheatsheet

A quick reference for generating RSA key pairs and AES keys with OpenSSL, either from the command line or the C API.

## Index
* [Quick start](#quick-start)
* [RSA key pairs](#rsa-key-pairs)
  * [Generate a private key (CLI)](#generate-a-private-key-cli)
  * [Derive the public key (CLI)](#derive-the-public-key-cli)
  * [Generate a key pair in C](#generate-a-key-pair-in-c)
* [AES keys](#aes-keys)
  * [Generate a random key (CLI)](#generate-a-random-key-cli)
  * [Generate a key in C](#generate-a-key-in-c)
* [RSA vs. AES: which one, when](#rsa-vs-aes-which-one-when)

---

# Quick start

```sh
# RSA key pair (private key; public key is derived from it)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out private-key.pem
openssl pkey -in private-key.pem -pubout -out public-key.pem

# AES key (256-bit, random, hex-encoded so it's easy to read/copy)
openssl rand -hex 32 > aes-key.hex
```

That's it for the CLI side. If you're generating these from C instead of the command line, jump to [Generate a key pair in C](#generate-a-key-pair-in-c) or [Generate a key in C](#generate-a-key-in-c).

**Never commit key files to Git.** Add to `.gitignore`:
```gitignore
private-key.pem
aes-key.hex
```

---

# RSA key pairs

RSA gives you two mathematically linked keys: a **public** key you can share freely, and a **private** key you must never share. Data encrypted with the public key can only be decrypted with the matching private key.

## Generate a private key (CLI)

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out private-key.pem
```

| Flag | Meaning |
|------|---------|
| `genpkey` | OpenSSL's modern key-generation subcommand |
| `-algorithm RSA` | Generate an RSA key |
| `-pkeyopt rsa_keygen_bits:3072` | Key size in bits. Use at least 2048; 3072 is a safer default |
| `-out` | File to write the private key to |

Optional: add `-aes-256-cbc` to encrypt the key file with a passphrase you'll be prompted for. Without it, protect the file with permissions instead: `chmod 600 private-key.pem` (Linux/macOS).

## Derive the public key (CLI)

The public key is always derivable from the private key — same private key, same public key, every time:

```sh
openssl pkey -in private-key.pem -pubout -out public-key.pem
```

Inspect either key if you want to see the actual numbers:

```sh
openssl pkey -in private-key.pem -text -noout
```

## Generate a key pair in C

Use the modern `EVP_PKEY` API — not the older `RSA_*` functions, which are deprecated and disabled by default in OpenSSL 3.x.

```c
#include <openssl/evp.h>

EVP_PKEY *generate_rsa_keypair(void) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_name(NULL, "RSA", NULL);
    EVP_PKEY *pkey = NULL;

    if (!ctx) return NULL;

    if (EVP_PKEY_keygen_init(ctx) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        return NULL;
    }

    EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, 3072);

    if (EVP_PKEY_keygen(ctx, &pkey) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        return NULL;
    }

    EVP_PKEY_CTX_free(ctx);
    return pkey;   // caller must EVP_PKEY_free(pkey) when done
}
```

To write it out as PEM (e.g. to send the public key to someone else):

```c
#include <openssl/pem.h>

void write_private_key_pem(EVP_PKEY *pkey, const char *path) {
    FILE *fp = fopen(path, "w");
    PEM_write_PrivateKey(fp, pkey, NULL, NULL, 0, NULL, NULL); // NULL cipher = unencrypted
    fclose(fp);
}

void write_public_key_pem(EVP_PKEY *pkey, const char *path) {
    FILE *fp = fopen(path, "w");
    PEM_write_PUBKEY(fp, pkey);
    fclose(fp);
}
```

Check every return value in real code — the `<= 0` and `NULL` checks above are the minimum, not optional extras.

---

# AES keys

Unlike RSA, AES uses a single **symmetric** key: the same key encrypts and decrypts. It's just a block of random bytes — there's no mathematical structure to generate, only randomness to get right.

## Generate a random key (CLI)

```sh
openssl rand -hex 32   # 32 bytes = 256 bits, printed as hex
```

Save it to a file if you need to reuse it:

```sh
openssl rand -hex 32 > aes-key.hex
```

| Key size | Bytes | Flag |
|----------|-------|------|
| AES-128 | 16 | `openssl rand -hex 16` |
| AES-192 | 24 | `openssl rand -hex 24` |
| AES-256 | 32 | `openssl rand -hex 32` |

Use `-hex` for something you can read, copy-paste, or store in a text file. If you need raw bytes instead (e.g. to pipe directly into another program), drop `-hex` and redirect to a binary file:

```sh
openssl rand 32 > aes-key.bin
```

## Generate a key in C

Always use a cryptographically secure random source — never `rand()` or similar. OpenSSL's `RAND_bytes` is the right tool:

```c
#include <openssl/rand.h>

#define AES_KEY_LEN 32   // 256-bit key
#define GCM_IV_LEN  12   // 96-bit IV, standard for AES-GCM

int generate_aes_key_iv(unsigned char *key, unsigned char *iv) {
    if (RAND_bytes(key, AES_KEY_LEN) != 1) return -1;
    if (RAND_bytes(iv, GCM_IV_LEN) != 1) return -1;
    return 0;
}
```

**Always check the return value of `RAND_bytes`.** It returns `1` on success and anything else on failure — treating a failed call as if it succeeded means encrypting with a predictable or all-zero key.

Generate a **fresh IV for every message** you encrypt with the same key. Reusing an IV with AES-GCM breaks the confidentiality guarantee entirely — this is one of the most common real-world AES mistakes.

---

# RSA vs. AES: which one, when

| | RSA | AES |
|---|-----|-----|
| Key type | Key pair (public + private) | Single shared key |
| Speed | Slow | Fast |
| Data size limit | Yes — a 3072-bit key can only encrypt a few hundred bytes directly | No practical limit |
| Typical use | Encrypting a small AES key, or signing | Encrypting the actual data |

In practice, the two are almost always combined: use RSA once to securely hand over a randomly generated AES key, then use that AES key to encrypt everything else. This is the same pattern TLS itself uses under the hood.