import crypto from "crypto";

export type StreamType = "video" | "audio";

function sign(secret: string, payload: string): string {
  return crypto.createHmac("sha256", secret).update(payload).digest("base64url");
}

export function createStreamProxySignature(args: {
  secret: string;
  videoId: string;
  type: StreamType;
  exp: number;
}): string {
  const payload = `${args.videoId}.${args.type}.${args.exp}`;
  return sign(args.secret, payload);
}

export function verifyStreamProxySignature(args: {
  secret: string;
  videoId: string;
  type: StreamType;
  exp: number;
  sig: string;
}): boolean {
  if (!Number.isFinite(args.exp)) return false;
  if (!args.sig) return false;

  const expected = createStreamProxySignature(args);

  // timingSafeEqual requires equal-length buffers.
  const expectedBuf = Buffer.from(expected);
  const actualBuf = Buffer.from(args.sig);
  if (expectedBuf.length !== actualBuf.length) return false;

  return crypto.timingSafeEqual(expectedBuf, actualBuf);
}

