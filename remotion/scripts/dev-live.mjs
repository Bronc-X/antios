import { spawn, spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const remotionRoot = path.resolve(scriptDir, "..");
const syncScript = path.join(remotionRoot, "scripts", "sync-app-snapshot.mjs");
const npxCommand = process.platform === "win32" ? "npx.cmd" : "npx";

const initialSync = spawnSync(process.execPath, [syncScript], {
  cwd: remotionRoot,
  stdio: "inherit",
});

if (initialSync.status !== 0) {
  process.exit(initialSync.status ?? 1);
}

const syncWatcher = spawn(process.execPath, [syncScript, "--watch"], {
  cwd: remotionRoot,
  stdio: "inherit",
});

const studio = spawn(npxCommand, ["remotion", "studio"], {
  cwd: remotionRoot,
  stdio: "inherit",
});

const shutdown = () => {
  syncWatcher.kill("SIGTERM");
  studio.kill("SIGTERM");
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

studio.on("exit", (code) => {
  syncWatcher.kill("SIGTERM");
  process.exit(code ?? 0);
});

syncWatcher.on("exit", (code) => {
  if (code && code !== 0) {
    studio.kill("SIGTERM");
    process.exit(code);
  }
});
