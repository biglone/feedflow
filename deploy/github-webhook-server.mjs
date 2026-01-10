import crypto from "crypto";
import http from "http";
import { spawn } from "child_process";
import { URL } from "url";

const secret = process.env.GITHUB_WEBHOOK_SECRET;
if (!secret) {
  throw new Error("Missing env: GITHUB_WEBHOOK_SECRET");
}

const port = Number.parseInt(process.env.GITHUB_WEBHOOK_PORT ?? "9010", 10);
if (!Number.isFinite(port) || port <= 0) {
  throw new Error("Invalid env: GITHUB_WEBHOOK_PORT");
}

const webhookPath = process.env.GITHUB_WEBHOOK_PATH ?? "/_deploy/github";
const expectedRef = `refs/heads/${process.env.FEEDFLOW_BRANCH ?? "main"}`;
const deployScript =
  process.env.FEEDFLOW_DEPLOY_SCRIPT ??
  `${process.cwd()}/deploy/deploy-feedflow.sh`;

let running = null;

function json(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

function verifySignature(body, signatureHeader) {
  if (!signatureHeader || typeof signatureHeader !== "string") return false;

  const [algo, sigHex] = signatureHeader.split("=", 2);
  if (algo !== "sha256" || !sigHex) return false;

  const expected = crypto.createHmac("sha256", secret).update(body).digest("hex");
  const expectedBuf = Buffer.from(expected, "hex");
  const actualBuf = Buffer.from(sigHex, "hex");
  if (expectedBuf.length !== actualBuf.length) return false;

  return crypto.timingSafeEqual(expectedBuf, actualBuf);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
  if (req.method !== "POST" || url.pathname !== webhookPath) {
    res.statusCode = 404;
    res.end("Not Found");
    return;
  }

  const event = req.headers["x-github-event"];
  if (event !== "push") {
    json(res, 202, { ok: true, ignored: true, reason: "unsupported_event" });
    return;
  }

  const chunks = [];
  let total = 0;
  req.on("data", (chunk) => {
    total += chunk.length;
    if (total > 1_000_000) {
      req.destroy(new Error("Payload too large"));
      return;
    }
    chunks.push(chunk);
  });

  req.on("end", () => {
    const body = Buffer.concat(chunks);

    const signatureHeader = req.headers["x-hub-signature-256"];
    if (!verifySignature(body, signatureHeader)) {
      json(res, 401, { ok: false, error: "invalid_signature" });
      return;
    }

    let payload;
    try {
      payload = JSON.parse(body.toString("utf8"));
    } catch {
      json(res, 400, { ok: false, error: "invalid_json" });
      return;
    }

    if (payload?.ref !== expectedRef) {
      json(res, 202, { ok: true, ignored: true, reason: "branch_mismatch" });
      return;
    }

    if (running) {
      json(res, 202, { ok: true, queued: false, running: true });
      return;
    }

    running = spawn("/bin/bash", [deployScript], {
      stdio: "inherit",
      env: process.env,
    });

    running.on("exit", () => {
      running = null;
    });

    json(res, 202, { ok: true, started: true });
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`FeedFlow deploy webhook listening on 127.0.0.1:${port}${webhookPath}`);
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});

