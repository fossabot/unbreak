#!/usr/bin/env bash
#
# ccfix uninstaller (PRD v2 §9) — the counterpart to install.sh, for users who
# installed via the curl one-liner rather than Homebrew.
#
#   curl -fsSL https://raw.githubusercontent.com/OWNER/ccfix/main/uninstall.sh | bash
#
# It runs `ccfix uninstall` to tear down the login watcher, logs, undo socket,
# and config, then removes the `ccfix` binary itself. Homebrew users should run
# `brew uninstall ccfix` instead — this script declines to delete a brew-managed
# binary, since that would desync Homebrew's bookkeeping.
#
# Flags:
#   --keep-config    leave the config file in place (forwarded to `ccfix uninstall`)
#
# Overridable via env:
#   CCFIX_PREFIX     install prefix to look under; binary -> $PREFIX/bin/ccfix
set -euo pipefail

KEEP_CONFIG=0
for arg in "$@"; do
  case "$arg" in
    --keep-config) KEEP_CONFIG=1 ;;
    -h | --help)
      cat <<'USAGE'
ccfix uninstaller (for users who installed without Homebrew).

  curl -fsSL https://raw.githubusercontent.com/OWNER/ccfix/main/uninstall.sh | bash

Tears down ccfix state (login watcher, logs, undo socket, config) and removes the
`ccfix` binary. Homebrew users: run `brew uninstall ccfix` instead.

Options:
  --keep-config    leave the config file in place
  -h, --help       show this help

Env overrides:
  CCFIX_PREFIX     install prefix to look under (default: search the usual paths)
USAGE
      exit 0
      ;;
    *)
      echo "ccfix uninstall: unknown argument '$arg'" >&2
      exit 2
      ;;
  esac
done

# --- Locate the binary -----------------------------------------------------
# Prefer an explicit prefix, then PATH, then the prefixes install.sh might have
# used. `command -v` resolves symlinks-on-PATH for us.
BIN=""
if [ -n "${CCFIX_PREFIX:-}" ] && [ -x "$CCFIX_PREFIX/bin/ccfix" ]; then
  BIN="$CCFIX_PREFIX/bin/ccfix"
elif command -v ccfix >/dev/null 2>&1; then
  BIN="$(command -v ccfix)"
else
  for candidate in /usr/local/bin/ccfix "$HOME/.local/bin/ccfix"; do
    if [ -x "$candidate" ]; then
      BIN="$candidate"
      break
    fi
  done
fi

if [ -z "$BIN" ]; then
  echo "ccfix uninstall: no ccfix binary found on PATH or in the usual prefixes."
  echo "ccfix uninstall: if you installed via Homebrew, run: brew uninstall ccfix"
  exit 0
fi

# A Homebrew-managed binary must go through brew, not rm — bail with guidance.
RESOLVED="$BIN"
if command -v readlink >/dev/null 2>&1; then
  RESOLVED="$(readlink -f "$BIN" 2>/dev/null || echo "$BIN")"
fi
case "$RESOLVED" in
  */Cellar/* | */Homebrew/*)
    echo "ccfix uninstall: $BIN is Homebrew-managed. Remove it with:"
    echo "    brew uninstall ccfix"
    exit 0
    ;;
esac

# --- Tear down state, then the binary --------------------------------------
echo "ccfix uninstall: removing ccfix state via $BIN"
if [ "$KEEP_CONFIG" -eq 1 ]; then
  "$BIN" uninstall --keep-config || echo "ccfix uninstall: state cleanup reported an issue; continuing."
else
  "$BIN" uninstall || echo "ccfix uninstall: state cleanup reported an issue; continuing."
fi

# Remove the binary. Fall back to sudo only if the location isn't user-writable.
if rm -f "$BIN" 2>/dev/null; then
  echo "ccfix uninstall: removed $BIN"
elif command -v sudo >/dev/null 2>&1; then
  echo "ccfix uninstall: $BIN is not user-writable; removing with sudo"
  sudo rm -f "$BIN" && echo "ccfix uninstall: removed $BIN"
else
  echo "ccfix uninstall: could not remove $BIN (permission denied); delete it manually." >&2
  exit 1
fi

echo "ccfix uninstall: done."
