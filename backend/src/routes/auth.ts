import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { eq } from "drizzle-orm";
import { db } from "../db/index.js";
import { users } from "../db/schema.js";
import { hashPassword, verifyPassword, createToken } from "../lib/auth.js";

const authRouter = new Hono();

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

authRouter.post("/register", zValidator("json", registerSchema), async (c) => {
  const { email, password } = c.req.valid("json");

  const existingUser = await db.query.users.findFirst({
    where: eq(users.email, email),
  });

  if (existingUser) {
    return c.json({ error: "Email already registered" }, 400);
  }

  const passwordHash = await hashPassword(password);

  const [user] = await db
    .insert(users)
    .values({
      email,
      passwordHash,
    })
    .returning({ id: users.id, email: users.email });

  const token = await createToken(user.id);

  return c.json({
    user: { id: user.id, email: user.email },
    token,
  });
});

authRouter.post("/login", zValidator("json", loginSchema), async (c) => {
  const { email, password } = c.req.valid("json");

  const user = await db.query.users.findFirst({
    where: eq(users.email, email),
  });

  if (!user) {
    return c.json({ error: "Invalid email or password" }, 401);
  }

  const isValidPassword = await verifyPassword(password, user.passwordHash);

  if (!isValidPassword) {
    return c.json({ error: "Invalid email or password" }, 401);
  }

  const token = await createToken(user.id);

  return c.json({
    user: { id: user.id, email: user.email },
    token,
  });
});

authRouter.get("/me", async (c) => {
  const authHeader = c.req.header("Authorization");

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  const token = authHeader.slice(7);
  const { verifyToken } = await import("../lib/auth");
  const payload = await verifyToken(token);

  if (!payload) {
    return c.json({ error: "Invalid token" }, 401);
  }

  const user = await db.query.users.findFirst({
    where: eq(users.id, payload.userId),
  });

  if (!user) {
    return c.json({ error: "User not found" }, 404);
  }

  return c.json({
    user: { id: user.id, email: user.email },
  });
});

export { authRouter };
