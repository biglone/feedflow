#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${FEEDFLOW_REPO_DIR:-$HOME/workspace/feedflow}"
BRANCH="${FEEDFLOW_BRANCH:-main}"
BACKEND_DIR="${FEEDFLOW_BACKEND_DIR:-backend}"
BACKEND_SERVICE="${FEEDFLOW_BACKEND_SERVICE:-feedflow-backend.service}"
LOCK_FILE="${FEEDFLOW_DEPLOY_LOCK:-$HOME/.cache/feedflow/deploy.lock}"

mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[deploy] another deploy is running"
  exit 0
fi

echo "[deploy] start: $(date -Is)"

if [[ "${FEEDFLOW_DEPLOY_ENABLE_PROXY:-1}" == "1" ]]; then
  export https_proxy="${https_proxy:-http://127.0.0.1:7890}"
  export http_proxy="${http_proxy:-http://127.0.0.1:7890}"
  export all_proxy="${all_proxy:-socks5://127.0.0.1:7890}"
  export HTTPS_PROXY="${HTTPS_PROXY:-$https_proxy}"
  export HTTP_PROXY="${HTTP_PROXY:-$http_proxy}"
  export ALL_PROXY="${ALL_PROXY:-$all_proxy}"
fi

git -C "$REPO_DIR" fetch origin "$BRANCH"

LOCAL="$(git -C "$REPO_DIR" rev-parse HEAD)"
REMOTE="$(git -C "$REPO_DIR" rev-parse "origin/$BRANCH")"

if [[ "$LOCAL" == "$REMOTE" ]]; then
  echo "[deploy] no changes (HEAD=$LOCAL)"
  exit 0
fi

NEEDS_NPM_CI=0
if git -C "$REPO_DIR" diff --name-only "$LOCAL" "$REMOTE" -- \
  "$BACKEND_DIR/package.json" "$BACKEND_DIR/package-lock.json" \
  | rg -q .; then
  NEEDS_NPM_CI=1
fi

echo "[deploy] update: $LOCAL -> $REMOTE"

systemctl --user stop "$BACKEND_SERVICE" || true

git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
git -C "$REPO_DIR" clean -fd \
  -e "$BACKEND_DIR/.env" \
  -e "$BACKEND_DIR/.env.*" \
  -e "$BACKEND_DIR/node_modules"

if [[ "$NEEDS_NPM_CI" == "1" ]] || [[ ! -d "$REPO_DIR/$BACKEND_DIR/node_modules" ]]; then
  echo "[deploy] npm ci (backend deps changed)"
  (cd "$REPO_DIR/$BACKEND_DIR" && npm ci --no-fund --no-audit)
fi

systemctl --user start "$BACKEND_SERVICE"

echo "[deploy] done: $(date -Is)"
