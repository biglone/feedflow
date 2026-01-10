#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${FEEDFLOW_REPO_DIR:-$HOME/workspace/feedflow-prod}"
BRANCH="${FEEDFLOW_BRANCH:-main}"
BACKEND_DIR="${FEEDFLOW_BACKEND_DIR:-backend}"
BACKEND_SERVICE="${FEEDFLOW_BACKEND_SERVICE:-feedflow-backend.service}"
LOCK_FILE="${FEEDFLOW_DEPLOY_LOCK:-$HOME/.cache/feedflow/deploy.lock}"

DEV_REPO_DIR_DEFAULT="$HOME/workspace/feedflow"
if [[ "$REPO_DIR" == "$DEV_REPO_DIR_DEFAULT" && "${FEEDFLOW_DEPLOY_ALLOW_DEV_DIR:-0}" != "1" ]]; then
  echo "[deploy] refusing: REPO_DIR points to dev dir ($DEV_REPO_DIR_DEFAULT)"
  echo "[deploy] set FEEDFLOW_REPO_DIR to a dedicated prod clone (e.g. ~/workspace/feedflow-prod)"
  echo "[deploy] or set FEEDFLOW_DEPLOY_ALLOW_DEV_DIR=1 to override (not recommended)"
  exit 1
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "[deploy] invalid repo dir (missing .git): $REPO_DIR"
  exit 1
fi

EXPECTED_ORIGIN="${FEEDFLOW_DEPLOY_EXPECTED_ORIGIN:-}"
if [[ -n "$EXPECTED_ORIGIN" ]]; then
  ACTUAL_ORIGIN="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$ACTUAL_ORIGIN" ]]; then
    echo "[deploy] missing git remote: origin"
    exit 1
  fi

  NORMALIZED_EXPECTED="${EXPECTED_ORIGIN%.git}"
  NORMALIZED_ACTUAL="${ACTUAL_ORIGIN%.git}"
  if [[ "$NORMALIZED_EXPECTED" != "$NORMALIZED_ACTUAL" ]]; then
    echo "[deploy] refusing: origin mismatch"
    echo "[deploy] expected: $EXPECTED_ORIGIN"
    echo "[deploy] actual:   $ACTUAL_ORIGIN"
    exit 1
  fi
fi

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

echo "[deploy] npm run build (backend)"
(cd "$REPO_DIR/$BACKEND_DIR" && npm run build)

systemctl --user start "$BACKEND_SERVICE"

echo "[deploy] done: $(date -Is)"
