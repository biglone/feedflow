import { createRequire } from "node:module";

type PackageJson = {
  name?: string;
  version?: string;
};

const require = createRequire(import.meta.url);
const pkg = require("../package.json") as PackageJson;

export const appName = pkg.name ?? "feedflow-backend";
export const appVersion = pkg.version ?? "0.0.0";

