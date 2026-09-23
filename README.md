# OpenSSL Cheatsheets

Quick-reference guides for common cryptographic tasks with OpenSSL — from the command line and from C using the `EVP_*` API.

## Guides

| Guide | Covers |
|-------|--------|
| [Key Generation Cheatsheet](./docs/keygen-cheatsheet.md) | Generating RSA key pairs and AES keys, via CLI and in C |
| [PKI Setup Cheatsheet](./docs/pki-setup-cheatsheet.md) | Setting up a Certificate Authority, generating and signing CSRs, and using the resulting certificate |

## Where to start

* Just need a RSA key pair or an AES key? → [Key Generation Cheatsheet](./docs/keygen-cheatsheet.md)
* Need a full CA-signed certificate for a server? → [PKI Setup Cheatsheet](./docs/pki-setup-cheatsheet.md)

Both guides are self-contained — start with whichever matches what you're building. The PKI guide covers RSA key generation as part of its own quick start, so you don't need to read the key generation guide first if certificates are all you're after.

Both guides require OpenSSL 3.0 or newer — see [Installation](#installation) below before you start either one.

---

# Installation

## Install OpenSSL

| Platform | Command |
|----------|---------|
| Windows (MSYS2 MINGW64 shell) | `pacman -S --needed make mingw-w64-x86_64-gcc mingw-w64-x86_64-openssl mingw-w64-x86_64-pkgconf` |
| macOS (Homebrew) | `xcode-select --install` then `brew install openssl@3 pkgconf` |
| Debian / Ubuntu | `sudo apt-get install build-essential libssl-dev pkg-config openssl` |
| Fedora / RHEL | `sudo dnf install gcc make openssl-devel pkgconf-pkg-config openssl` |

> **Windows:** Use the *MSYS2 MINGW64* shell (`C:\msys64\mingw64.exe`, or find it in the Start menu) — not Git Bash. Both shells identify themselves as `MINGW64`, but Git Bash ships its own OpenSSL and doesn't have `pacman`. Run `cygpath -w /` to check you're in the right one — it should print your MSYS2 folder.

> **macOS:** The `openssl` binary that ships with macOS is actually LibreSSL, not OpenSSL. Homebrew's real OpenSSL isn't added to your `PATH` automatically, so either call it as `$(brew --prefix openssl@3)/bin/openssl` or add that folder to your `PATH`.

## Verify your setup

This repository includes a `Makefile` and `openssl_check.c` that together confirm the OpenSSL headers, libraries, and compiler all work together. From the repo root:

```sh
make
```

If your compiler, `pkg-config`, or OpenSSL can't be found, this prints the exact command to install what's missing for your platform. It doesn't install anything itself.

| Command | Description |
|---------|-------------|
| `make run` | Same as `make`, but keeps the compiled binary around |
| `make clean` | Removes the compiled binary |

Also check your OpenSSL version — everything here needs **3.0 or newer**:

```sh
openssl version
```