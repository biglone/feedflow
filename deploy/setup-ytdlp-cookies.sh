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

cookie_entries="$(grep -v '^#' "$DEST_COOKIES_PATH" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')"
if [[ "$cookie_entries" =~ ^[0-9]+$ ]] && [[ "$cookie_entries" -lt 30 ]]; then
  echo "[cookies] warning: cookies file only has ${cookie_entries} entries; it may be incomplete (logged-out session)"
  echo "[cookies] hint: if some videos still hit bot-check, export cookies while logged in to https://www.youtube.com (or YouTube Music) and reinstall"
fi

systemctl --user restart "$BACKEND_SERVICE"
systemctl --user --no-pager -n 10 status "$BACKEND_SERVICE" || true

if [[ -f "$BACKEND_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$BACKEND_ENV_FILE"
  set +a
fi

if command -v yt-dlp >/dev/null 2>&1; then
  verify_video_id="${FEEDFLOW_YTDLP_VERIFY_VIDEO_ID:-dQw4w9WgXcQ}"
  verify_url="https://www.youtube.com/watch?v=${verify_video_id}"
  verify_err="$(mktemp)"

  if yt-dlp --cookies "$DEST_COOKIES_PATH" -q --no-warnings --skip-download "$verify_url" >/dev/null 2>"$verify_err"; then
    echo "[cookies] verify: yt-dlp can extract (${verify_video_id})"
  else
    err_line="$(grep -m 1 '^ERROR:' "$verify_err" || tail -n 1 "$verify_err")"
    err_line="${err_line#ERROR: }"
    echo "[cookies] warning: yt-dlp verify failed (${verify_video_id})"
    if [[ -n "$err_line" ]]; then
      echo "[cookies] details: $err_line"
    fi
    echo "[cookies] hint: if this is a bot-check, switch proxy/VPN exit (prefer residential) or solve the bot-check in a browser using the same exit IP, then re-export cookies"
  fi

  rm -f "$verify_err" || true
fi

echo "[cookies] done"
