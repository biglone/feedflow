import crypto from "crypto";
import http from "http";
import { spawn } from "child_process";
import { URL, fileURLToPath } from "url";

const secret = process.env.GITHUB_WEBHOOK_SECRET;
if (!secret) {
  throw new Error("Missing env: GITHUB_WEBHOOK_SECRET");
}

const port = Number.parseInt(process.env.GITHUB_WEBHOOK_PORT ?? "9010", 10);
if (!Number.isFinite(port) || port <= 0) {
  throw new Error("Invalid env: GITHUB_WEBHOOK_PORT");
}

const host = process.env.GITHUB_WEBHOOK_HOST ?? "127.0.0.1";
const webhookPath = process.env.GITHUB_WEBHOOK_PATH ?? "/_deploy/github";
const expectedRef = `refs/heads/${process.env.FEEDFLOW_BRANCH ?? "main"}`;
const expectedRepo = process.env.GITHUB_WEBHOOK_REPO;
const deployScript =
  process.env.FEEDFLOW_DEPLOY_SCRIPT ??
  fileURLToPath(new URL("./deploy-feedflow.sh", import.meta.url));
const maxBytes = Number.parseInt(process.env.GITHUB_WEBHOOK_MAX_BYTES ?? "1000000", 10);
if (!Number.isFinite(maxBytes) || maxBytes <= 0) {
  throw new Error("Invalid env: GITHUB_WEBHOOK_MAX_BYTES");
}

let running = null;
let pending = false;

function json(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

function header(req, name) {
  const value = req.headers[name];
  if (Array.isArray(value)) return value[0];
  return value;
}

function verifySignature(body, signatureHeader256, signatureHeaderSha1) {
  const allowSha1 = process.env.GITHUB_WEBHOOK_ALLOW_SHA1 === "1";

  if (typeof signatureHeader256 === "string" && signatureHeader256.length > 0) {
    const [algo, sigHex] = signatureHeader256.split("=", 2);
    if (algo !== "sha256" || !sigHex || sigHex.length !== 64) return false;

    const expected = crypto.createHmac("sha256", secret).update(body).digest("hex");
    const expectedBuf = Buffer.from(expected, "hex");
    const actualBuf = Buffer.from(sigHex, "hex");
    if (expectedBuf.length !== actualBuf.length) return false;

    return crypto.timingSafeEqual(expectedBuf, actualBuf);
  }

  if (
    allowSha1 &&
    typeof signatureHeaderSha1 === "string" &&
    signatureHeaderSha1.length > 0
  ) {
    const [algo, sigHex] = signatureHeaderSha1.split("=", 2);
    if (algo !== "sha1" || !sigHex || sigHex.length !== 40) return false;

    const expected = crypto.createHmac("sha1", secret).update(body).digest("hex");
    const expectedBuf = Buffer.from(expected, "hex");
    const actualBuf = Buffer.from(sigHex, "hex");
    if (expectedBuf.length !== actualBuf.length) return false;

    return crypto.timingSafeEqual(expectedBuf, actualBuf);
  }

  return false;
}

function startDeploy() {
  if (running) return;

  running = spawn("/bin/bash", [deployScript], {
    stdio: "inherit",
    env: process.env,
  });

  running.on("error", (err) => {
    console.error("[webhook] deploy spawn failed:", err);
    running = null;
  });

  running.on("exit", (code, signal) => {
    console.log("[webhook] deploy finished:", { code, signal });
    running = null;

    if (!pending) return;
    pending = false;
    startDeploy();
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
  if (req.method !== "POST" || url.pathname !== webhookPath) {
    res.statusCode = 404;
    res.end("Not Found");
    return;
  }

  const chunks = [];
  let total = 0;
  let aborted = false;
  req.on("data", (chunk) => {
    total += chunk.length;
    if (total > maxBytes) {
      json(res, 413, { ok: false, error: "payload_too_large" });
      aborted = true;
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });

  req.on("end", () => {
    if (aborted) return;
    const body = Buffer.concat(chunks);

    const signatureHeader256 = header(req, "x-hub-signature-256");
    const signatureHeaderSha1 = header(req, "x-hub-signature");
    if (!verifySignature(body, signatureHeader256, signatureHeaderSha1)) {
      json(res, 401, { ok: false, error: "invalid_signature" });
      return;
    }

    const event = header(req, "x-github-event");
    if (event === "ping") {
      json(res, 200, { ok: true });
      return;
    }

    let payload;
    try {
      payload = JSON.parse(body.toString("utf8"));
    } catch {
      json(res, 400, { ok: false, error: "invalid_json" });
      return;
    }

    if (expectedRepo && payload?.repository?.full_name !== expectedRepo) {
      json(res, 202, { ok: true, ignored: true, reason: "repo_mismatch" });
      return;
    }

    if (event !== "push") {
      json(res, 202, { ok: true, ignored: true, reason: "unsupported_event" });
      return;
    }

    if (payload?.ref !== expectedRef) {
      json(res, 202, { ok: true, ignored: true, reason: "branch_mismatch" });
      return;
    }

    if (payload?.deleted) {
      json(res, 202, { ok: true, ignored: true, reason: "ref_deleted" });
      return;
    }

    if (running) {
      pending = true;
      json(res, 202, { ok: true, queued: true, running: true });
      return;
    }

    startDeploy();
    json(res, 202, { ok: true, started: true });
  });
});

server.listen(port, host, () => {
  console.log(`FeedFlow deploy webhook listening on ${host}:${port}${webhookPath}`);
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});
