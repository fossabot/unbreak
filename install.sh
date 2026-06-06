#!/usr/bin/env bash
#
# ccfix fallback installer (PRD v2 §9) — for users without Homebrew.
#
#   curl -fsSL https://raw.githubusercontent.com/OWNER/ccfix/main/install.sh | bash
#
# Builds the `ccfix` binary from a tagged source release and installs it. It does
# NOT enable the clipboard watcher: per §8.2 the watcher is opt-in. Pass
# `--enable-watch` to also install the per-user login LaunchAgent (templated by
# `ccfix install-agent`, so there is no hardcoded path or username).
#
# Overridable via env:
#   CCFIX_REPO     owner/repo to fetch from        (default: OWNER/ccfix)
#   CCFIX_VERSION  git tag to install              (default: v0.1.0)
#   CCFIX_PREFIX   install prefix; binary -> $PREFIX/bin/ccfix
#                  (default: /usr/local if writable, else ~/.local)
set -euo pipefail

REPO="${CCFIX_REPO:-OWNER/ccfix}"
VERSION="${CCFIX_VERSION:-v0.1.0}"
ENABLE_WATCH=0
for arg in "$@"; do
  case "$arg" in
    --enable-watch) ENABLE_WATCH=1 ;;
    -h | --help)
      cat <<'USAGE'
ccfix fallback installer (for users without Homebrew).

  curl -fsSL https://raw.githubusercontent.com/OWNER/ccfix/main/install.sh | bash

Builds and installs the `ccfix` CLI from a tagged source release. The clipboard
watcher stays OFF unless you pass --enable-watch (or run `ccfix setup` later).

Options:
  --enable-watch   also install the per-user login LaunchAgent (ccfix install-agent)
  -h, --help       show this help

Env overrides:
  CCFIX_REPO       owner/repo to fetch from   (default: OWNER/ccfix)
  CCFIX_VERSION    git tag to install         (default: v0.1.0)
  CCFIX_PREFIX     install prefix             (default: /usr/local or ~/.local)
USAGE
      exit 0
      ;;
    *)
      echo "ccfix install: unknown argument '$arg'" >&2
      exit 2
      ;;
  esac
done

err() {
  echo "ccfix install: $*" >&2
  exit 1
}

# --- Preflight -------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || err "macOS only (this is a native macOS utility)."
command -v swift >/dev/null 2>&1 ||
  err "the Swift toolchain is required. Install the Xcode Command Line Tools:
    xcode-select --install"
command -v curl >/dev/null 2>&1 || err "curl is required."

# Choose an install prefix we can actually write to.
if [ -n "${CCFIX_PREFIX:-}" ]; then
  PREFIX="$CCFIX_PREFIX"
elif [ -w /usr/local/bin ] || { [ -d /usr/local ] && [ -w /usr/local ]; }; then
  PREFIX="/usr/local"
else
  PREFIX="$HOME/.local"
fi
BINDIR="$PREFIX/bin"

# --- Fetch + build ---------------------------------------------------------
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
TARBALL="https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz"

echo "ccfix install: downloading $REPO@$VERSION"
curl -fsSL "$TARBALL" -o "$WORKDIR/src.tar.gz" ||
  err "failed to download $TARBALL"
tar -xzf "$WORKDIR/src.tar.gz" -C "$WORKDIR"
SRCDIR="$(find "$WORKDIR" -maxdepth 1 -type d -name 'ccfix-*' | head -n1)"
[ -n "$SRCDIR" ] || err "unexpected archive layout."

echo "ccfix install: building (release)"
(cd "$SRCDIR" && swift build -c release) || err "build failed."
BUILT="$SRCDIR/.build/release/ccfix"
[ -x "$BUILT" ] || err "build did not produce a ccfix binary."

# --- Install ---------------------------------------------------------------
mkdir -p "$BINDIR"
install -m 0755 "$BUILT" "$BINDIR/ccfix"
echo "ccfix install: installed $BINDIR/ccfix"

case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "ccfix install: note — $BINDIR is not on your PATH; add it to your shell profile." ;;
esac

# --- Watcher (opt-in) ------------------------------------------------------
if [ "$ENABLE_WATCH" -eq 1 ]; then
  echo "ccfix install: enabling the login watcher"
  "$BINDIR/ccfix" install-agent
else
  cat <<EOF

The clipboard watcher is OFF until you opt in. Enable it with the guided setup:
    ccfix setup
or directly install the login LaunchAgent:
    ccfix install-agent

One-shot use never needs the watcher:
    pbpaste | ccfix -
EOF
fi
