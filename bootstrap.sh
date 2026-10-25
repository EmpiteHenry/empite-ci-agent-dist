#!/usr/bin/env bash
# bootstrap.sh — one-line installer for empite-ci-agent (Linux / macOS).
#
# Detects OS + CPU, downloads the matching release bundle (or uses the binary
# next to this script when run from an unpacked bundle), installs it to
# /usr/local/bin, writes the agent env file (0600) and installs + starts the
# OS service (systemd on Linux, launchd on macOS).
#
# Usage (the one-liner you share):
#   curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/bootstrap.sh | bash
#
# Knobs (env vars; anything unset is prompted for unless ASSUME_YES=1):
#   EMPITE_SERVER          server gRPC address, host:port (required)
#   EMPITE_AGENT_SECRET    shared agent secret or an org enrolment token (required)
#   EMPITE_ENROLL_TOKEN    alias for EMPITE_AGENT_SECRET (org enrolment token)
#   EMPITE_AGENT_LABELS    extra labels, comma-separated key=value
#   EMPITE_BACKEND         auto-detect (default), docker, local or dummy
#   EMPITE_GRPC_SECURE     true to dial the server with TLS
#   REPO=owner/name        public releases repo (default below)
#   VERSION=v1.2.0         pin a release tag (default: latest)
#   BASE_URL=…             download base override, e.g. file:///path/to/dist
#   PREFIX=/usr/local      install prefix (binary goes to $PREFIX/bin)
#   ASSUME_YES=1           non-interactive: never prompt, fail on missing values
set -euo pipefail

REPO="${REPO:-EmpiteHenry/empite-ci-agent-dist}"
VERSION="${VERSION:-latest}"
PREFIX="${PREFIX:-/usr/local}"
BIN="empite-ci-agent"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1; }

bold "empite-ci-agent bootstrap"

# ── detect platform ────────────────────────────────────────────────────────
case "$(uname -s)" in
    Darwin) GOOS=darwin; ENV_FILE=/usr/local/etc/empite-ci/agent.env ;;
    Linux)  GOOS=linux;  ENV_FILE=/etc/empite-ci/agent.env ;;
    *) die "unsupported OS '$(uname -s)' — on Windows use install.ps1";;
esac
case "$(uname -m)" in
    x86_64|amd64)  GOARCH=amd64 ;;
    arm64|aarch64) GOARCH=arm64 ;;
    *) die "unsupported CPU arch '$(uname -m)'";;
esac
ok "platform: $GOOS/$GOARCH"

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    need sudo || die "run as root (or install sudo)"
    SUDO="sudo"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/empite-ci-bootstrap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ── get the binary ─────────────────────────────────────────────────────────
# Run from an unpacked bundle: the binary sits next to this script.
SELF_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch() { # fetch <url> <out>
    local url="$1" out="$2"
    case "$url" in
        file://*) cp "${url#file://}" "$out" ;;
        *) if need curl; then curl -fsSL "$url" -o "$out"; else wget -qO "$out" "$url"; fi ;;
    esac
}

if [[ -n "$SELF_DIR" && -x "$SELF_DIR/$BIN" && -z "${BASE_URL:-}" ]]; then
    SRC_BIN="$SELF_DIR/$BIN"
    ok "using bundled binary $SRC_BIN"
else
    if [[ -n "${BASE_URL:-}" ]]; then
        BASE="${BASE_URL%/}"
    elif [[ "$VERSION" == "latest" ]]; then
        BASE="https://github.com/$REPO/releases/latest/download"
    else
        BASE="https://github.com/$REPO/releases/download/$VERSION"
    fi
    [[ "$BASE" == file://* ]] || need curl || need wget || die "need curl or wget on PATH"
    need unzip || die "unzip not on PATH (needed to unpack the bundle)"
    bold "Downloading ${BIN}-${GOOS}-${GOARCH}.zip from $BASE"
    fetch "$BASE/${BIN}-${GOOS}-${GOARCH}.zip" "$WORK/bundle.zip" \
        || die "download failed: $BASE/${BIN}-${GOOS}-${GOARCH}.zip"
    unzip -q "$WORK/bundle.zip" -d "$WORK/bundle"
    SRC_BIN="$(find "$WORK/bundle" -maxdepth 2 -type f -name "$BIN" | head -1)"
    [[ -n "$SRC_BIN" ]] || die "bundle did not contain $BIN"
    ok "downloaded and unpacked"
fi

# ── settings ───────────────────────────────────────────────────────────────
: "${EMPITE_AGENT_SECRET:=${EMPITE_ENROLL_TOKEN:-}}"
: "${EMPITE_BACKEND:=auto-detect}"

# ask <var> <prompt> [secret]: prompt on the terminal (stdin is the script under curl|bash).
ask() {
    local var="$1" prompt="$2" secret="${3:-}" val=""
    [[ -n "${!var:-}" ]] && return 0
    if [[ "${ASSUME_YES:-}" == "1" ]] || ! [[ -r /dev/tty ]]; then
        return 0
    fi
    if [[ -n "$secret" ]]; then
        read -r -s -p "  $prompt: " val </dev/tty; echo >/dev/tty
    else
        read -r -p "  $prompt: " val </dev/tty
    fi
    printf -v "$var" '%s' "$val"
}

bold "Configuration"
ask EMPITE_SERVER "server gRPC address (host:port)"
ask EMPITE_AGENT_SECRET "agent secret or org enrolment token" secret
ask EMPITE_AGENT_LABELS "extra labels (key=value,…; empty for none)"
[[ -n "${EMPITE_SERVER:-}" ]] || die "EMPITE_SERVER is required"
[[ -n "${EMPITE_AGENT_SECRET:-}" ]] || die "EMPITE_AGENT_SECRET (or EMPITE_ENROLL_TOKEN) is required"
case "$EMPITE_BACKEND" in auto-detect|docker|local|dummy) ;; *) die "EMPITE_BACKEND must be auto-detect, docker, local or dummy";; esac
for v in "$EMPITE_SERVER" "$EMPITE_AGENT_SECRET" "${EMPITE_AGENT_LABELS:-}"; do
    [[ "$v" != *$'\n'* ]] || die "settings must be single-line values"
done
ok "server: $EMPITE_SERVER  backend: $EMPITE_BACKEND${EMPITE_AGENT_LABELS:+  labels: $EMPITE_AGENT_LABELS}"

# ── install ────────────────────────────────────────────────────────────────
DEST="$PREFIX/bin/$BIN"
bold "Installing"

# Upgrade path: stop + drop an existing service before replacing the binary.
if [[ -x "$DEST" ]]; then
    $SUDO "$DEST" service stop >/dev/null 2>&1 || true
    $SUDO "$DEST" service uninstall >/dev/null 2>&1 || true
fi
$SUDO mkdir -p "$PREFIX/bin"
$SUDO install -m 0755 "$SRC_BIN" "$DEST"
ok "binary → $DEST ($("$DEST" --version 2>/dev/null | head -1 || echo unknown version))"

{
    echo "# empite-ci-agent settings — written by bootstrap.sh"
    echo "EMPITE_SERVER=$EMPITE_SERVER"
    echo "EMPITE_AGENT_SECRET=$EMPITE_AGENT_SECRET"
    echo "EMPITE_BACKEND=$EMPITE_BACKEND"
    [[ -n "${EMPITE_AGENT_LABELS:-}" ]] && echo "EMPITE_AGENT_LABELS=$EMPITE_AGENT_LABELS"
    [[ -n "${EMPITE_GRPC_SECURE:-}" ]] && echo "EMPITE_GRPC_SECURE=$EMPITE_GRPC_SECURE"
    true
} > "$WORK/agent.env"
$SUDO mkdir -p "$(dirname "$ENV_FILE")"
$SUDO install -m 0600 "$WORK/agent.env" "$ENV_FILE"
ok "config → $ENV_FILE (0600)"

$SUDO "$DEST" service --config "$ENV_FILE" install >/dev/null
$SUDO "$DEST" service --config "$ENV_FILE" start >/dev/null
ok "service installed and started"
$SUDO "$DEST" service status || warn "service is not running yet — check the service logs"

echo
bold "Done. Uninstall with: uninstall.sh (add --purge to also remove $ENV_FILE)"
