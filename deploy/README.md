# FeedFlow 部署（GitHub Webhook 即时触发）

本目录提供一个「本机部署」方案：GitHub push → webhook → 本机执行 `deploy-feedflow.sh` → 重启后端服务。

为避免 `git reset/clean` 误伤开发目录，默认使用独立目录 `~/workspace/feedflow-prod` 作为生产运行目录。

## 1) 准备生产目录（feedflow-prod）

在开发仓库根目录执行：

```bash
./deploy/bootstrap-feedflow-prod.sh
```

可选参数：

- 复制开发环境的 `backend/.env` 到生产目录（仅当生产目录不存在该文件时）：
  - `FEEDFLOW_COPY_ENV=1 ./deploy/bootstrap-feedflow-prod.sh`

## 2) 配置环境变量

后端会通过 `dotenv/config` 从工作目录读取 `backend/.env`（推荐放在生产目录）：

- `~/workspace/feedflow-prod/backend/.env`（参考 `backend/.env.example`）

Webhook + 部署脚本使用 systemd 环境文件（不要提交到 git）：

- `~/.config/feedflow/deploy.env`（从 `deploy/systemd/deploy.env.example` 复制）
- `~/.config/feedflow/backend.env`（可选；从 `deploy/systemd/backend.env.example` 复制，用于给 systemd 后端服务配置代理等环境变量）

## 3) systemd（user）服务

安装 unit 文件：

```bash
mkdir -p ~/.config/systemd/user
cp deploy/systemd/feedflow-backend.service ~/.config/systemd/user/
cp deploy/systemd/feedflow-deploy-webhook.service ~/.config/systemd/user/
systemctl --user daemon-reload
```

日志文件（推荐用于复盘 / 排障）：

- 后端：`~/.cache/feedflow/backend.log`
- Webhook + 部署脚本输出：`~/.cache/feedflow/deploy-webhook.log`

准备 webhook 环境文件：

```bash
mkdir -p ~/.config/feedflow
cp deploy/systemd/deploy.env.example ~/.config/feedflow/deploy.env
chmod 600 ~/.config/feedflow/deploy.env
```

启动并设置开机自启：

```bash
systemctl --user enable --now feedflow-backend.service
systemctl --user enable --now feedflow-deploy-webhook.service
```

## 4) GitHub Webhook 配置

GitHub 仓库 Settings → Webhooks：

- Payload URL：`https://<你的域名>/_deploy/github`
- Content type：`application/json`
- Secret：与 `~/.config/feedflow/deploy.env` 的 `GITHUB_WEBHOOK_SECRET` 一致
- Events：选择 `Just the push event`

`deploy/github-webhook-server.mjs` 默认只监听 `127.0.0.1:9010`，建议用 Nginx/Caddy 反代暴露到公网并启用 HTTPS。

Nginx 示例（仅示意）：

```nginx
location /_deploy/github {
  proxy_pass http://127.0.0.1:9010;
  proxy_set_header Host $host;
  client_max_body_size 1m;
}
```

如果你使用 Cloudflare Tunnel（cloudflared），需要把 `/_deploy/github` 路径转发到 `http://localhost:9010`，并把站点其余路径转发到后端 `http://localhost:3000`，例如：

```yaml
ingress:
  - hostname: feedflow.example.com
    path: /_deploy/github
    service: http://localhost:9010
  - hostname: feedflow.example.com
    service: http://localhost:3000
  - service: http_status:404
```

## 安全要点

- 必须设置 `GITHUB_WEBHOOK_SECRET`，服务端会校验 `X-Hub-Signature-256`（默认不接受 SHA1）。
- 建议设置 `GITHUB_WEBHOOK_REPO=owner/feedflow`，只允许来自指定仓库的 webhook。
- `deploy/deploy-feedflow.sh` 默认拒绝在 `~/workspace/feedflow`（开发目录）执行；如需覆盖需显式设置 `FEEDFLOW_DEPLOY_ALLOW_DEV_DIR=1`。
