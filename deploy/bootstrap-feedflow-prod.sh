#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEV_REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

REPO_DIR="${FEEDFLOW_REPO_DIR:-$HOME/workspace/feedflow-prod}"
BRANCH="${FEEDFLOW_BRANCH:-main}"
REPO_URL="${FEEDFLOW_REPO_URL:-}"

if [[ -z "$REPO_URL" ]]; then
  if git -C "$DEV_REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REPO_URL="$(git -C "$DEV_REPO_DIR" remote get-url origin)"
  fi
fi

if [[ -z "$REPO_URL" ]]; then
  echo "[bootstrap] missing FEEDFLOW_REPO_URL (or run from a git clone with origin remote)"
  exit 1
fi

mkdir -p "$(dirname "$REPO_DIR")"

if [[ -d "$REPO_DIR/.git" ]]; then
  echo "[bootstrap] using existing repo: $REPO_DIR"
  git -C "$REPO_DIR" remote set-url origin "$REPO_URL" >/dev/null 2>&1 || true
else
  if [[ -e "$REPO_DIR" ]]; then
    echo "[bootstrap] refusing: path exists but is not a git repo: $REPO_DIR"
    exit 1
  fi

  echo "[bootstrap] cloning $REPO_URL -> $REPO_DIR"
  git clone "$REPO_URL" "$REPO_DIR"
fi

git -C "$REPO_DIR" fetch origin "$BRANCH" --prune
git -C "$REPO_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
git -C "$REPO_DIR" reset --hard "origin/$BRANCH"

if [[ "${FEEDFLOW_COPY_ENV:-0}" == "1" ]]; then
  if [[ -f "$DEV_REPO_DIR/backend/.env" && ! -f "$REPO_DIR/backend/.env" ]]; then
    cp "$DEV_REPO_DIR/backend/.env" "$REPO_DIR/backend/.env"
    echo "[bootstrap] copied backend/.env"
  fi
fi

if [[ "${FEEDFLOW_INSTALL_DEPS:-1}" == "1" ]]; then
  echo "[bootstrap] npm ci (backend)"
  (cd "$REPO_DIR/backend" && npm ci --no-fund --no-audit)
fi

if [[ "${FEEDFLOW_BUILD_BACKEND:-1}" == "1" ]]; then
  echo "[bootstrap] npm run build (backend)"
  (cd "$REPO_DIR/backend" && npm run build)
fi

echo "[bootstrap] done"
