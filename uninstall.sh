#!/usr/bin/env bash
# uninstall.sh — remove empite-ci-agent from this machine (Linux / macOS).
#
# The mirror of bootstrap.sh: stops and uninstalls the OS service (systemd /
# launchd), deletes the binary and, with --purge, the env file and agent state.
# Self-contained, so it works as a one-liner too:
#
#   curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/uninstall.sh | bash -s -- --purge
#
# Knobs:
#   --purge / PURGE=1     also remove the env file dir and the agent state dir
#   PREFIX=/usr/local     install prefix bootstrap.sh used
set -euo pipefail

BIN="empite-ci-agent"
PREFIX="${PREFIX:-/usr/local}"
PURGE="${PURGE:-}"
for a in "$@"; do
    case "$a" in
        --purge) PURGE=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$a" >&2; exit 2 ;;
    esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

case "$(uname -s)" in
    Darwin) CONF_DIR=/usr/local/etc/empite-ci; STATE_DIR=/usr/local/var/empite-ci
            UNIT=/Library/LaunchDaemons/$BIN.plist ;;
    *)      CONF_DIR=/etc/empite-ci; STATE_DIR=/var/lib/empite-ci
            UNIT=/etc/systemd/system/$BIN.service ;;
esac

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || { echo "run as root (or install sudo)" >&2; exit 1; }
    SUDO="sudo"
fi

bold "empite-ci-agent uninstaller"

# ── service ────────────────────────────────────────────────────────────────
DEST="$PREFIX/bin/$BIN"
[[ -x "$DEST" ]] || DEST="$(command -v "$BIN" 2>/dev/null || true)"
if [[ -n "$DEST" && -x "$DEST" ]]; then
    $SUDO "$DEST" service stop >/dev/null 2>&1 || true
    $SUDO "$DEST" service uninstall >/dev/null 2>&1 || true
fi
# Belt and braces when the binary is already gone (or the unit outlived it).
if [[ -f "$UNIT" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        $SUDO launchctl unload "$UNIT" 2>/dev/null || true
    else
        $SUDO systemctl disable --now "$BIN" 2>/dev/null || true
    fi
    $SUDO rm -f "$UNIT"
fi
command -v systemctl >/dev/null 2>&1 && $SUDO systemctl daemon-reload 2>/dev/null || true
ok "service removed"

# ── binary ─────────────────────────────────────────────────────────────────
if [[ -n "$DEST" && -e "$DEST" ]]; then
    $SUDO rm -f "$DEST"
    ok "removed $DEST"
else
    warn "no $BIN binary found"
fi

# ── config + state ─────────────────────────────────────────────────────────
if [[ "$PURGE" == "1" ]]; then
    $SUDO rm -rf "$CONF_DIR" "$STATE_DIR"
    ok "purged $CONF_DIR and $STATE_DIR"
else
    [[ -e "$CONF_DIR" ]] && warn "kept $CONF_DIR (re-run with --purge to remove it)"
fi

bold "Done."
