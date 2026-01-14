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

## 2.1) 配置 YouTube cookies（解决 bot-check）

如果 `/api/youtube/stream/*` 返回 “Sign in to confirm you’re not a bot / Please sign in to continue”，需要给 `yt-dlp` 提供 cookies。

### 导出 cookies（推荐 Chrome）

1) 在浏览器里确认你已经登录 YouTube（右上角有头像）。
2) 安装一个能导出 Netscape `cookies.txt` 的扩展（例如 Chrome 的 `Get cookies.txt LOCALLY`）。
3) 打开 `https://www.youtube.com`（不要用 `m.youtube.com`），用扩展导出 `cookies.txt`。
4) 拷贝到服务器（例如放到 `/tmp/cookies.txt`）。

推荐把 cookies 文件保存在主机本地（不要放在仓库目录，也不要提交到 git）：

- 目标路径：`~/.config/feedflow/yt-dlp-cookies.txt`（`chmod 600`）
- 在 `~/.config/feedflow/backend.env` 增加：`YTDLP_COOKIES_PATH=...`

提供了一个辅助脚本：

```bash
./deploy/setup-ytdlp-cookies.sh /path/to/cookies.txt
```

### 快速验证（推荐）

`setup-ytdlp-cookies.sh` 会在重启后端后，自动用 `yt-dlp` 做一次「可解析性」校验并输出结果。

你也可以指定一个你当前失败的视频来验证（不会输出 cookies 内容）：

```bash
FEEDFLOW_YTDLP_VERIFY_VIDEO_ID=FE-hM1kRK4Y ./deploy/setup-ytdlp-cookies.sh /tmp/cookies.txt
```

或者手动验证（可选，便于对比代理/环境差异）：

```bash
source ~/.config/feedflow/backend.env
yt-dlp --cookies ~/.config/feedflow/yt-dlp-cookies.txt --skip-download https://www.youtube.com/watch?v=FE-hM1kRK4Y
```

## 2.2) 配置 PO Token Provider（可选，解决「部分视频仍然 bot-check」）

YouTube 近期对部分视频开始强制要求 PO Token（即使 cookies 已配置，依然可能出现 “Sign in to confirm you’re not a bot”）。

推荐使用 yt-dlp 的 PO Token Provider 插件（bgutil）自动生成 token（不需要每个视频手动抓 token）：

```bash
./deploy/setup-ytdlp-pot-provider.sh
```

该脚本会：

- 安装 `bgutil-ytdlp-pot-provider` 的 yt-dlp 插件（放在 `~/.config/yt-dlp/plugins/`）
- 在本机启动一个 Node.js provider 服务（默认端口 `4416`），并注册为 systemd user 服务：`feedflow-bgutil-pot-provider.service`

如果你的网络无法访问 Docker Hub（镜像拉取超时），这个脚本会优先走「原生 Node.js」方式（从 GitHub clone 并 `npm install` / `npx tsc`）。

## 2.5) 初始化数据库（必须）

首次部署或更新数据表后，需要执行一次迁移：

```bash
cd ~/workspace/feedflow-prod/backend
npm run db:migrate
```

本仓库的 `deploy/deploy-feedflow.sh` 默认会在每次部署后执行迁移（可用 `FEEDFLOW_RUN_DB_MIGRATE=0` 关闭）。

Webhook + 部署脚本使用 systemd 环境文件（不要提交到 git）：

- `~/.config/feedflow/deploy.env`（从 `deploy/systemd/deploy.env.example` 复制）
- `~/.config/feedflow/backend.env`（可选；从 `deploy/systemd/backend.env.example` 复制，用于给 systemd 后端服务配置代理等环境变量）

## 3) systemd（user）服务

安装 unit 文件：

```bash
mkdir -p ~/.config/systemd/user
cp deploy/systemd/feedflow-backend.service ~/.config/systemd/user/
cp deploy/systemd/feedflow-deploy-webhook.service ~/.config/systemd/user/
# 可选：PO Token provider（仅当你配置了 bgutil）
cp deploy/systemd/feedflow-bgutil-pot-provider.service ~/.config/systemd/user/
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
# 可选：PO Token provider（仅当你配置了 bgutil）
systemctl --user enable --now feedflow-bgutil-pot-provider.service
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
