#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy/setup-ytdlp-pot-provider.sh

Installs a yt-dlp PO Token Provider plugin (bgutil) and starts a local provider
HTTP server (Node.js) via systemd user service.

Why:
- Some YouTube videos return: "Sign in to confirm you're not a bot"
- Cookies may not be sufficient for all videos; PO Tokens can help

Env vars (optional):
  BGUTIL_POT_PROVIDER_VERSION   Provider/plugin version (default: 1.2.2)
  BGUTIL_PROVIDER_DIR           Where to clone/build the provider (default: ~/workspace/bgutil-ytdlp-pot-provider)
  YTDLP_PLUGINS_DIR             yt-dlp plugins dir (default: ~/.config/yt-dlp/plugins)
  FEEDFLOW_BACKEND_ENV_FILE     Backend env file to source for proxy vars (default: ~/.config/feedflow/backend.env)

Notes:
- This script does NOT store any secrets in git.
- It uses the "native Node.js" provider method (Docker Hub may be unreachable in some networks).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="${BGUTIL_POT_PROVIDER_VERSION:-1.2.2}"
PLUGIN_URL="https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/${VERSION}/bgutil-ytdlp-pot-provider.zip"

YTDLP_PLUGINS_DIR="${YTDLP_PLUGINS_DIR:-$HOME/.config/yt-dlp/plugins}"
PLUGIN_ZIP_PATH="$YTDLP_PLUGINS_DIR/bgutil-ytdlp-pot-provider.zip"

BGUTIL_PROVIDER_DIR="${BGUTIL_PROVIDER_DIR:-$HOME/workspace/bgutil-ytdlp-pot-provider}"
BACKEND_ENV_FILE="${FEEDFLOW_BACKEND_ENV_FILE:-$HOME/.config/feedflow/backend.env}"

SERVICE_NAME="feedflow-bgutil-pot-provider.service"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[pot] missing dependency: $1" >&2
    exit 1
  fi
}

require_cmd git
require_cmd node
require_cmd npm
require_cmd systemctl
require_cmd curl

mkdir -p "$YTDLP_PLUGINS_DIR"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "[pot] install yt-dlp plugin: $PLUGIN_ZIP_PATH"
curl -sS -L "$PLUGIN_URL" -o "$tmp"
install -m 644 -T "$tmp" "$PLUGIN_ZIP_PATH"

echo "[pot] clone/build provider: $BGUTIL_PROVIDER_DIR"
if [[ -d "$BGUTIL_PROVIDER_DIR/.git" ]]; then
  git -C "$BGUTIL_PROVIDER_DIR" fetch --tags --force
  git -C "$BGUTIL_PROVIDER_DIR" checkout -q "$VERSION"
else
  git clone --single-branch --branch "$VERSION" \
    https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git \
    "$BGUTIL_PROVIDER_DIR"
fi

cd "$BGUTIL_PROVIDER_DIR/server"

if [[ -f "$BACKEND_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$BACKEND_ENV_FILE"
  set +a
fi

npm install --no-fund --no-audit
npx tsc

mkdir -p "$SYSTEMD_USER_DIR" "$HOME/.cache/feedflow"
install -m 644 -T "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/systemd/${SERVICE_NAME}" \
  "$SYSTEMD_USER_DIR/$SERVICE_NAME"

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME"

echo "[pot] verify: provider ping"
curl -sS http://127.0.0.1:4416/ping || true

if command -v yt-dlp >/dev/null 2>&1; then
  if yt-dlp -v --skip-download "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>&1 | grep -F "[pot] PO Token Providers: bgutil:" >/dev/null; then
    echo "[pot] verify: yt-dlp sees bgutil PO Token providers"
  else
    echo "[pot] warning: yt-dlp plugin not detected (check $PLUGIN_ZIP_PATH)" >&2
  fi
fi

systemctl --user --no-pager -n 20 status "$SERVICE_NAME" || true

echo "[pot] done"

