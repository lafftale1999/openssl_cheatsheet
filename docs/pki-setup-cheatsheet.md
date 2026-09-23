# PKI Setup Cheatsheet

A quick-start guide to setting up a small Public Key Infrastructure (PKI) with your own Certificate Authority: generating keys, requesting a certificate, and getting it signed.

> **Before you start:** make sure OpenSSL 3.0+ is installed — see the [Installation section in the top-level README](../README.md#installation).

## Index
* [Quick start](#quick-start)
* [Repository layout](#repository-layout)
* [Generate RSA keys](#generate-rsa-keys)
* [Generate a Certificate Signing Request (CSR)](#generate-a-certificate-signing-request-csr)
* [Create a Certificate Authority (CA)](#create-a-certificate-authority-ca)
* [Sign the CSR](#sign-the-csr)
* [Use the certificate](#use-the-certificate)

---

# Quick start

Get a working, CA-signed certificate in 7 steps. Everything is explained in more detail further down — come back here once you understand the pieces.

1. Edit `./config/csr.cnf`: set `CN` to your server's name, and replace the `DNS.*` / `IP.*` entries under `[alt_names]` with the actual name(s) and IP address(es) of your server.
2. Create the output folders:
   ```sh
   mkdir -p ca server
   ```
3. Create the CA (you'll be asked to set a passphrase for the CA key — remember it, you'll need it again):
   ```sh
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -aes-256-cbc -out ./ca/ca-key.pem
   openssl req -x509 -new -key ./ca/ca-key.pem -sha256 -days 3650 -config ./config/ca.cnf -out ./ca/ca.crt
   ```
4. Create the server's private key and CSR:
   ```sh
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out ./server/private-key.pem
   openssl req -new -key ./server/private-key.pem -sha256 -config ./config/csr.cnf -out ./server/request.csr
   ```
5. Sign the CSR with your CA:
   ```sh
   openssl x509 -req -in ./server/request.csr -CA ./ca/ca.crt -CAkey ./ca/ca-key.pem -sha256 -days 365 \
       -extfile ./config/server-ext.cnf -copy_extensions copy -out ./server/server.crt
   ```
6. Verify it worked — this should print `./server/server.crt: OK`:
   ```sh
   openssl verify -CAfile ./ca/ca.crt ./server/server.crt
   ```
7. Point your server at `./server/server.crt` and `./server/private-key.pem`, and import `./ca/ca.crt` as a trusted root on any client that needs to connect (see [Use the certificate](#use-the-certificate)).

> **Never commit `ca-key.pem` or `private-key.pem` to Git.** Add them to `.gitignore` — see [Repository layout](#repository-layout).

---

# Repository layout

| Folder | Contents |
|--------|----------|
| `./ca/` | The CA's config, private key, and certificate |
| `./server/` | The server's config, private key, CSR, and signed certificate |

OpenSSL won't create folders for you — make them first:

```sh
mkdir -p ca server
```

**Never commit private keys.** Add this to `.gitignore` before you generate anything:

```gitignore
ca/ca-key.pem
server/private-key.pem
```

# Generate RSA keys

RSA gives you a key **pair**: a public key and a private key, mathematically linked. Anything encrypted with the public key can only be decrypted with the private key, and a signature made with the private key can be verified with the public key. Share the public key freely; never share the private key.

### Private key

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out ./server/private-key.pem
```

* Use at least 2048 bits — 3072 is a safer default if the key needs to stay valid past 2030.
* Add `-aes-256-cbc` to encrypt the key file with a passphrase. Server keys are often left unencrypted so the server can restart without a human typing a password — if you do that, lock the file down instead: `chmod 600 ./server/private-key.pem` (Linux/macOS).

### Public key

The public key is derived from the private key — same private key always gives the same public key:

```sh
openssl pkey -in ./server/private-key.pem -pubout -out ./server/public-key.pem
```

You don't strictly need this file to make a CSR (OpenSSL pulls the public key from the private key automatically), but it's handy whenever you need to hand your public key to someone else.

> For a closer look at RSA (and AES) key generation, including the C API, see the [Key Generation Cheatsheet](./keygen-cheatsheet.md).

# Generate a Certificate Signing Request (CSR)

A CSR is what you send to a CA to ask for a certificate. It bundles your public key with identifying info (your *subject* — e.g. domain name, organization) and is signed with your private key to prove you actually hold that key. The CA checks the request and, if it's happy, hands back a signed certificate.

Your private key never leaves your machine — it's not part of the CSR and should never be sent anywhere.

### Configure the request

Edit `./config/csr.cnf` to match your server before generating the CSR:

```ini
[req]
prompt             = no
distinguished_name = dn
req_extensions     = req_ext

[dn]
C  = SE
L  = Stockholm
O  = Example AB
CN = example.com

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = example.com
DNS.2 = www.example.com
IP.1  = 192.168.1.10
```

| Section | What it does | What to change |
|---------|---------------|-----------------|
| `[req]` | General settings; `prompt = no` reads everything from this file instead of asking interactively | Nothing |
| `[dn]` | Your subject: `C` country code, `L` city, `O` organization, `CN` common name | Fill in your own values — `CN` is usually your server's main name or IP |
| `[req_ext]` | Tells OpenSSL to include the SAN list below | Nothing |
| `[alt_names]` | Every DNS name and IP address the certificate should cover | Match these to your actual server |

* List **every** name and IP a client might use to connect. Most TLS clients (browsers included) ignore `CN` entirely and only check the SAN list.
* Number entries from 1 with no gaps: `DNS.1`, `DNS.2`, `IP.1`, `IP.2`, ...
* Skip the `DNS.*` lines if you're only using an IP address — but then that IP needs to stay fixed, or the certificate stops matching.
* Public CAs won't issue certificates for private IPs (`192.168.x.x`, `10.x.x.x`, etc.) — that's exactly what your own CA is for.

### Create the CSR

```sh
openssl req -new -key ./server/private-key.pem -sha256 -config ./config/csr.cnf -out ./server/request.csr
```

| Flag | Meaning |
|------|---------|
| `req` | The OpenSSL subcommand for CSRs |
| `-new` | Create a new CSR |
| `-key` | The private key to sign it with (and pull the public key from) |
| `-sha256` | Hash algorithm used for the signature |
| `-config` | The config file with your subject and SAN |
| `-out` | Where to save the CSR |

### Inspect and check a CSR

See what's inside, and confirm the signature is valid:

```sh
openssl req -in ./server/request.csr -noout -text -verify
```

Confirm a CSR actually matches a given private key — both commands should print the same hash:

```sh
openssl req -in ./server/request.csr -noout -pubkey | openssl sha256
openssl pkey -in ./server/private-key.pem -pubout | openssl sha256
```

# Create a Certificate Authority (CA)

Before anything can be signed, you need a CA — the root of trust for your setup. Any device that trusts your CA automatically trusts every certificate the CA has signed, so clients only need to know the CA, not every individual server.

The CA has its own key pair: it signs requests with its private key, and publishes its certificate (with the public key) so others can verify those signatures.

| File | Contains | Who should have it |
|------|----------|---------------------|
| `./ca/ca-key.pem` | The CA's private key | Only the CA. Anyone with this file can mint certificates your clients will trust |
| `./ca/ca.crt` | The CA's certificate + public key | Everyone — clients import this as a trusted root |

### CA private key

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -aes-256-cbc -out ./ca/ca-key.pem
```

You'll be prompted for a passphrase — always set one here. This is the most sensitive file in the whole setup. You'll need this passphrase every time you sign something.

### Configure the CA

Edit `./config/ca.cnf`:

```ini
[req]
prompt             = no
distinguished_name = dn
x509_extensions    = v3_ca

[dn]
C  = SE
O  = Example AB
CN = Example AB Internal CA

[v3_ca]
basicConstraints       = critical, CA:TRUE, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
```

| Setting | What it does | What to change |
|---------|----------------|-----------------|
| `[dn]` | The CA's name — becomes the *issuer* on every certificate it signs | Your own values; give `CN` a name people will recognize |
| `basicConstraints` | `CA:TRUE` marks this as a CA cert; `pathlen:0` means it can sign servers but not other CAs | Nothing |
| `keyUsage` | Restricts the key to signing certs and revocation lists | Nothing |
| `subjectKeyIdentifier` / `authorityKeyIdentifier` | Helps clients find the right CA cert | Nothing |

`critical` means: if a client doesn't understand this extension, it must reject the certificate rather than ignore it.

### CA certificate

```sh
openssl req -x509 -new -key ./ca/ca-key.pem -sha256 -days 3650 -config ./config/ca.cnf -out ./ca/ca.crt
```

| Flag | Meaning |
|------|---------|
| `-x509` | Create a self-signed certificate instead of a CSR — a root CA signs itself since there's nothing above it |
| `-key` | The CA's private key |
| `-days 3650` | Valid for 10 years. Once it expires, everything it signed stops being trusted |
| `-config` | The CA's config file |
| `-out` | Where to save the CA certificate |

# Sign the CSR

A CSR needs to be signed by a CA the client trusts. Here, you *are* the CA. (With a public CA, you'd instead upload the CSR and they'd verify domain ownership before signing — you never get their private key.)

### Configure what the certificate is allowed to do

Edit `./config/server-ext.cnf`:

```ini
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid, issuer
```

| Setting | Meaning |
|---------|---------|
| `basicConstraints` | `CA:FALSE` — this cert can't be used to sign other certs |
| `keyUsage` | Allowed for signatures and key exchange during a TLS handshake |
| `extendedKeyUsage` | `serverAuth` — only valid for a TLS server |
| `subjectKeyIdentifier` / `authorityKeyIdentifier` | Identify this cert's key and the CA that issued it |

You usually don't need to touch this file — the names and IPs come from the CSR itself.

### Check before signing

Always inspect a CSR before signing it — a CA should never sign something it hasn't checked:

```sh
openssl req -in ./server/request.csr -noout -text -verify
```

### Sign it

```sh
openssl x509 -req -in ./server/request.csr -CA ./ca/ca.crt -CAkey ./ca/ca-key.pem -sha256 -days 365 \
    -extfile ./config/server-ext.cnf -copy_extensions copy -out ./server/server.crt
```

| Flag | Meaning |
|------|---------|
| `x509 -req` | Build a certificate from a CSR |
| `-in` | The CSR to sign |
| `-CA` | The CA certificate — its name becomes the issuer of the new cert |
| `-CAkey` | The CA's private key, used to create the signature (you'll be asked for its passphrase) |
| `-sha256` | Hash algorithm for the signature |
| `-days 365` | Valid for 1 year — shorter validity limits the damage if the key ever leaks |
| `-extfile` | The extensions the CA applies |
| `-copy_extensions copy` | Copies the SAN from the CSR without letting the CSR override anything already set in `-extfile` (so a CSR can't sneakily make itself a CA) |
| `-out` | Where to save the signed certificate |

A random serial number is generated for you automatically.

### Verify the result

```sh
openssl verify -CAfile ./ca/ca.crt ./server/server.crt
openssl x509 -in ./server/server.crt -noout -subject -issuer -enddate -ext subjectAltName
```

The first command should print `./server/server.crt: OK`.

# Use the certificate

Your server needs two files:

* `./server/server.crt` — the signed certificate, presented to clients during the TLS handshake
* `./server/private-key.pem` — the matching private key, which never leaves the server

Any client connecting to it needs to trust `./ca/ca.crt` (never `ca-key.pem`):

| Platform | How |
|----------|-----|
| Windows | `certmgr.msc` → *Trusted Root Certification Authorities* → *Certificates* → right-click → *All Tasks* → *Import* |
| macOS | Open *Keychain Access*, drag in `ca.crt`, add it to the *System* keychain, set it to *Always Trust* |
| Debian / Ubuntu | `sudo cp ./ca/ca.crt /usr/local/share/ca-certificates/example-ca.crt` then `sudo update-ca-certificates` |

Some apps (Firefox, Java) keep their own certificate store and need the CA imported separately.

### Try it out

Start a quick test server:

```sh
openssl s_server -accept 8443 -cert ./server/server.crt -key ./server/private-key.pem -www
```

Then, from another terminal, connect to it (swap in your server's actual IP from the SAN):

```sh
openssl s_client -connect 192.168.1.10:8443 -CAfile ./ca/ca.crt -verify_ip 192.168.1.10 -verify_return_error </dev/null
```

You should see `Verify return code: 0 (ok)`. If the IP isn't in the certificate's SAN, you'll get `IP address mismatch` instead.