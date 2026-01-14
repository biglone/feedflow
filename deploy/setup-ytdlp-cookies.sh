#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy/setup-ytdlp-cookies.sh <cookies.txt path>
  deploy/setup-ytdlp-cookies.sh -    # read cookies.txt from stdin

Installs a yt-dlp cookies.txt file on this host (outside the git repo) and wires
the backend systemd user service to use it via YTDLP_COOKIES_PATH.

Notes:
- Never commit cookies to git.
- The backend service is restarted after installation.
EOF
}

COOKIES_SRC="${1:-}"
if [[ -z "$COOKIES_SRC" ]] || [[ "$COOKIES_SRC" == "-h" ]] || [[ "$COOKIES_SRC" == "--help" ]]; then
  usage
  exit 1
fi

CONFIG_DIR="${FEEDFLOW_CONFIG_DIR:-$HOME/.config/feedflow}"
DEST_COOKIES_PATH="${FEEDFLOW_YTDLP_COOKIES_PATH:-$CONFIG_DIR/yt-dlp-cookies.txt}"
BACKEND_ENV_FILE="${FEEDFLOW_BACKEND_ENV_FILE:-$CONFIG_DIR/backend.env}"
BACKEND_SERVICE="${FEEDFLOW_BACKEND_SERVICE:-feedflow-backend.service}"

mkdir -p "$CONFIG_DIR"

tmp=""
cleanup() {
  if [[ -n "${tmp:-}" && -f "$tmp" ]]; then
    rm -f "$tmp"
  fi
}
trap cleanup EXIT

if [[ "$COOKIES_SRC" == "-" ]]; then
  tmp="$(mktemp)"
  cat >"$tmp"
  install -m 600 -T "$tmp" "$DEST_COOKIES_PATH"
else
  if [[ ! -f "$COOKIES_SRC" ]]; then
    echo "[cookies] missing file: $COOKIES_SRC" >&2
    exit 1
  fi
  install -m 600 -T "$COOKIES_SRC" "$DEST_COOKIES_PATH"
fi

touch "$BACKEND_ENV_FILE"
chmod 600 "$BACKEND_ENV_FILE" || true

if grep -q "^YTDLP_COOKIES_PATH=" "$BACKEND_ENV_FILE"; then
  tmp="$(mktemp)"
  awk -v path="$DEST_COOKIES_PATH" '
    /^YTDLP_COOKIES_PATH=/ { print "YTDLP_COOKIES_PATH=" path; next }
    { print }
  ' "$BACKEND_ENV_FILE" >"$tmp"
  mv "$tmp" "$BACKEND_ENV_FILE"
else
  {
    echo ""
    echo "# yt-dlp cookies (required when YouTube returns bot-check)"
    echo "YTDLP_COOKIES_PATH=$DEST_COOKIES_PATH"
  } >>"$BACKEND_ENV_FILE"
fi

echo "[cookies] installed: $DEST_COOKIES_PATH"
echo "[cookies] updated:   $BACKEND_ENV_FILE"

systemctl --user restart "$BACKEND_SERVICE"
systemctl --user --no-pager -n 10 status "$BACKEND_SERVICE" || true

if command -v curl >/dev/null 2>&1; then
  if curl -sS -m 20 -b "$DEST_COOKIES_PATH" "https://www.youtube.com" 2>/dev/null | grep -F '"LOGGED_IN":true' >/dev/null; then
    echo "[cookies] verify: YouTube logged-in session detected"
  else
    echo "[cookies] warning: YouTube logged-in session not detected; cookies may be incomplete/expired"
    echo "[cookies] hint: export cookies while logged in to https://www.youtube.com and rerun this script"
  fi
fi

echo "[cookies] done"
