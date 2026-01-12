import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import * as schema from "./schema.js";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error(
    "Missing DATABASE_URL. Set it in backend/.env (see backend/.env.example)."
  );
}

const sql = neon<boolean, boolean>(databaseUrl);
export const db = drizzle(sql, { schema });

export type Database = typeof db;
