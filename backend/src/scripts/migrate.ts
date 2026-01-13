import "dotenv/config";
import { migrate } from "drizzle-orm/neon-http/migrator";
import { db } from "../db/index.js";

async function main() {
  const migrationsFolder = process.env.DRIZZLE_MIGRATIONS_FOLDER || "drizzle";
  await migrate(db, { migrationsFolder });
  console.log(`[db:migrate] migrations applied from '${migrationsFolder}'`);
}

main().catch((error) => {
  console.error("[db:migrate] failed", error);
  process.exit(1);
});

