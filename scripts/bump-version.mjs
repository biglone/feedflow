#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

function usage() {
  console.log(`Usage:
  node scripts/bump-version.mjs <newVersion> [--build <n> | --inc-build]

Examples:
  node scripts/bump-version.mjs 1.1.0
  node scripts/bump-version.mjs 1.1.0 --inc-build
  node scripts/bump-version.mjs 1.1.0 --build 42
`);
}

function assertSemver(version) {
  const semverRegex =
    /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;
  if (!semverRegex.test(version)) {
    throw new Error(`Invalid version "${version}". Expected SemVer like 1.2.3`);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function updatePackageVersion({ packageJsonPath, packageLockPath, version }) {
  const pkg = readJson(packageJsonPath);
  pkg.version = version;
  writeJson(packageJsonPath, pkg);

  if (!fs.existsSync(packageLockPath)) return;
  const lock = readJson(packageLockPath);
  lock.version = version;
  if (lock.packages?.[""]) {
    lock.packages[""].version = version;
  }
  writeJson(packageLockPath, lock);
}

function updateXcodeGenProjectYml({ projectYmlPath, version, build }) {
  const original = fs.readFileSync(projectYmlPath, "utf8");
  const lines = original.split(/\r?\n/);

  let didUpdateVersion = false;
  let didUpdateBuild = false;

  const updated = lines.map((line) => {
    if (line.match(/^\s*MARKETING_VERSION:\s*".*"\s*$/)) {
      didUpdateVersion = true;
      return line.replace(/MARKETING_VERSION:\s*".*"/, `MARKETING_VERSION: "${version}"`);
    }
    if (build != null && line.match(/^\s*CURRENT_PROJECT_VERSION:\s*".*"\s*$/)) {
      didUpdateBuild = true;
      return line.replace(/CURRENT_PROJECT_VERSION:\s*".*"/, `CURRENT_PROJECT_VERSION: "${build}"`);
    }
    return line;
  });

  if (!didUpdateVersion) {
    throw new Error(`Failed to update MARKETING_VERSION in ${projectYmlPath}`);
  }
  if (build != null && !didUpdateBuild) {
    throw new Error(`Failed to update CURRENT_PROJECT_VERSION in ${projectYmlPath}`);
  }

  fs.writeFileSync(projectYmlPath, updated.join("\n"), "utf8");
}

function updateXcodeProjectPbxproj({ pbxprojPath, version, build }) {
  if (!fs.existsSync(pbxprojPath)) return;
  const original = fs.readFileSync(pbxprojPath, "utf8");

  let updated = original.replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${version};`);
  if (build != null) {
    updated = updated.replace(/CURRENT_PROJECT_VERSION = [^;]+;/g, `CURRENT_PROJECT_VERSION = ${build};`);
  }

  if (updated === original) {
    throw new Error(`Failed to update version settings in ${pbxprojPath}`);
  }

  fs.writeFileSync(pbxprojPath, updated, "utf8");
}

function parseArgs(argv) {
  const args = argv.slice(2);
  const version = args[0];
  if (!version || version === "-h" || version === "--help") {
    usage();
    process.exit(version ? 0 : 1);
  }

  let build = null;
  let incBuild = false;

  for (let i = 1; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === "--build") {
      const raw = args[i + 1];
      if (!raw) throw new Error("Missing value for --build");
      const parsed = Number.parseInt(raw, 10);
      if (!Number.isFinite(parsed) || parsed < 1) {
        throw new Error(`Invalid --build "${raw}" (expected integer >= 1)`);
      }
      build = String(parsed);
      i += 1;
      continue;
    }
    if (arg === "--inc-build") {
      incBuild = true;
      continue;
    }
    throw new Error(`Unknown arg: ${arg}`);
  }

  return { version, build, incBuild };
}

function main() {
  const { version, build, incBuild } = parseArgs(process.argv);
  assertSemver(version);

  const repoRoot = process.cwd();

  const backendPackageJsonPath = path.join(repoRoot, "backend", "package.json");
  const backendPackageLockPath = path.join(repoRoot, "backend", "package-lock.json");
  const iosProjectYmlPath = path.join(repoRoot, "ios", "project.yml");
  const iosPbxprojPath = path.join(repoRoot, "ios", "FeedFlow.xcodeproj", "project.pbxproj");

  const previousProjectYml = fs.readFileSync(iosProjectYmlPath, "utf8");
  const currentBuildMatch = previousProjectYml.match(/^\s*CURRENT_PROJECT_VERSION:\s*"([^"]+)"\s*$/m);
  const currentBuild = currentBuildMatch?.[1];

  let nextBuild = build;
  if (nextBuild == null && incBuild) {
    const parsed = Number.parseInt(currentBuild ?? "", 10);
    nextBuild = String(Number.isFinite(parsed) && parsed > 0 ? parsed + 1 : 1);
  }

  updateXcodeGenProjectYml({
    projectYmlPath: iosProjectYmlPath,
    version,
    build: nextBuild,
  });
  updateXcodeProjectPbxproj({
    pbxprojPath: iosPbxprojPath,
    version,
    build: nextBuild,
  });

  updatePackageVersion({
    packageJsonPath: backendPackageJsonPath,
    packageLockPath: backendPackageLockPath,
    version,
  });

  console.log("Updated versions:");
  console.log(`- ios/project.yml: MARKETING_VERSION=${version}${nextBuild ? ` CURRENT_PROJECT_VERSION=${nextBuild}` : ""}`);
  if (fs.existsSync(iosPbxprojPath)) {
    console.log(`- ios/FeedFlow.xcodeproj/project.pbxproj: MARKETING_VERSION=${version}${nextBuild ? ` CURRENT_PROJECT_VERSION=${nextBuild}` : ""}`);
  }
  console.log(`- backend/package.json: version=${version}`);
  if (fs.existsSync(backendPackageLockPath)) {
    console.log(`- backend/package-lock.json: version=${version}`);
  }
  console.log("");
  console.log("Next steps:");
  console.log(`- git commit -am "chore(release): v${version}"`);
  console.log(`- git tag -a "v${version}" -m "v${version}"`);
  console.log("- git push && git push --tags");
}

try {
  main();
} catch (err) {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
}
