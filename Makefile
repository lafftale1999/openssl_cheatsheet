# Makefile - build and run the OpenSSL installation check.
#
# Supported environments:
#   Windows : MSYS2 shell (UCRT64, MINGW64 or CLANG64) with its own gcc/clang
#   macOS   : Homebrew or MacPorts OpenSSL, Apple clang or gcc
#   Linux   : distro OpenSSL development package
#
# Usage:
#   make          check environment, build, run, then remove the binary
#   make run      same, but keep the binary
#   make clean    remove build output
#
# Requires GNU make (3.81 or newer, which is what macOS ships).

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
ifeq ($(OS),Windows_NT)
  PLATFORM := windows
else
  UNAME_S := $(shell uname -s)
  ifeq ($(UNAME_S),Darwin)
    PLATFORM := macos
  else
    PLATFORM := linux
  endif
endif

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
# Only override make's built-in default; respect CC=... from the command line.
ifeq ($(origin CC),default)
  ifeq ($(PLATFORM),windows)
    CC := gcc
  else
    CC := cc
  endif
endif
PKG_CONFIG ?= pkg-config

TARGET := openssl_check
ifeq ($(PLATFORM),windows)
  BIN := $(TARGET).exe
else
  BIN := $(TARGET)
endif

# ---------------------------------------------------------------------------
# Platform specifics: install hints, pkg-config search path, dependency tool
# ---------------------------------------------------------------------------
PKG_CONFIG_EXTRA :=

ifeq ($(PLATFORM),windows)
  LIBDEPS_CMD := ldd
  ifneq ($(MINGW_PACKAGE_PREFIX),)
    INSTALL_HINT := pacman -S --needed $(MINGW_PACKAGE_PREFIX)-gcc $(MINGW_PACKAGE_PREFIX)-openssl $(MINGW_PACKAGE_PREFIX)-pkgconf
  else
    INSTALL_HINT := open an MSYS2 UCRT64 or MINGW64 shell and install <prefix>-gcc, <prefix>-openssl and <prefix>-pkgconf with pacman
  endif

else ifeq ($(PLATFORM),macos)
  LIBDEPS_CMD := otool -L
  # Homebrew's openssl@3 is keg-only, so pkg-config does not find it by default.
  BREW_OPENSSL := $(shell brew --prefix openssl@3 2>/dev/null)
  ifneq ($(wildcard $(BREW_OPENSSL)/lib/pkgconfig),)
    PKG_CONFIG_EXTRA := $(BREW_OPENSSL)/lib/pkgconfig
  endif
  INSTALL_HINT := brew install openssl@3 pkgconf   (or with MacPorts: sudo port install openssl3 pkgconfig)

else
  LIBDEPS_CMD := ldd
  ifneq ($(shell command -v apt-get 2>/dev/null),)
    INSTALL_HINT := sudo apt-get install build-essential libssl-dev pkg-config
  else ifneq ($(shell command -v dnf 2>/dev/null),)
    INSTALL_HINT := sudo dnf install gcc make openssl-devel pkgconf-pkg-config
  else ifneq ($(shell command -v pacman 2>/dev/null),)
    INSTALL_HINT := sudo pacman -S --needed base-devel openssl pkgconf
  else ifneq ($(shell command -v zypper 2>/dev/null),)
    INSTALL_HINT := sudo zypper install gcc make libopenssl-devel pkg-config
  else ifneq ($(shell command -v apk 2>/dev/null),)
    INSTALL_HINT := sudo apk add build-base openssl-dev pkgconf
  else
    INSTALL_HINT := install a C compiler, pkg-config and the OpenSSL development package for your distribution
  endif
endif

# Pass the extra search path explicitly: older GNU make (e.g. 3.81 on macOS)
# does not export variables to $(shell ...).
ifneq ($(PKG_CONFIG_EXTRA),)
  PKGCONF := PKG_CONFIG_PATH="$(PKG_CONFIG_EXTRA)$(if $(PKG_CONFIG_PATH),:$(PKG_CONFIG_PATH))" $(PKG_CONFIG)
else
  PKGCONF := $(PKG_CONFIG)
endif

OPENSSL_CFLAGS := $(shell $(PKGCONF) --cflags openssl 2>/dev/null)
OPENSSL_LIBS   := $(shell $(PKGCONF) --libs openssl 2>/dev/null)

CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra $(OPENSSL_CFLAGS)
LDLIBS += $(OPENSSL_LIBS)

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
.PHONY: all check-env run clean

# Print which OpenSSL shared libraries the binary resolves at runtime.
define show_libs
	@echo
	@if command -v $(firstword $(LIBDEPS_CMD)) >/dev/null; then \
	    echo "OpenSSL libraries loaded at runtime:"; \
	    $(LIBDEPS_CMD) ./$(BIN) | grep -iE 'ssl|crypto' || true; echo; fi
endef

# Default: build, run, then remove the binary. The binary is removed even if
# a check fails, and make still exits with the program's exit code.
all: $(BIN)
	$(show_libs)
	@./$(BIN); status=$$?; rm -f $(BIN); echo "Removed $(BIN)"; exit $$status

check-env:
	@echo "Platform: $(PLATFORM)"
	@echo "Compiler: $$(command -v $(CC) || echo '<not found>')"
ifeq ($(PLATFORM),windows)
	@echo "MSYSTEM:  $${MSYSTEM:-<not set>}"
	@if [ "$$MSYSTEM" = "MSYS" ] || [ -z "$$MSYSTEM" ]; then \
	    echo "WARNING: use an MSYS2 UCRT64 or MINGW64 shell, not the MSYS shell or cmd"; fi
	@if [ -n "$$MINGW_PREFIX" ] && [ "$$(command -v $(CC))" != "$$MINGW_PREFIX/bin/$(CC)" ]; then \
	    echo "WARNING: $(CC) is not from $$MINGW_PREFIX - toolchain and libraries may not match"; fi
endif
	@command -v $(CC) >/dev/null || { \
	    echo "ERROR: $(CC) not found. Install: $(INSTALL_HINT)"; exit 1; }
	@command -v $(PKG_CONFIG) >/dev/null || { \
	    echo "ERROR: $(PKG_CONFIG) not found. Install: $(INSTALL_HINT)"; exit 1; }
	@$(PKGCONF) --exists openssl || { \
	    echo "ERROR: pkg-config cannot find openssl. Install: $(INSTALL_HINT)"; exit 1; }
	@echo "OpenSSL (pkg-config): $$($(PKGCONF) --modversion openssl)"
	@echo "CFLAGS: $(OPENSSL_CFLAGS)"
	@echo "LIBS:   $(OPENSSL_LIBS)"
	@echo

$(BIN): $(TARGET).c | check-env
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

# Build and run, but keep the binary (useful for debugging).
run: $(BIN)
	$(show_libs)
	./$(BIN)

clean:
	rm -f $(BIN)