// Sets one environment variable in a Vercel project's production settings, with the value read from
// the ENV_VALUE environment variable, so the value is never on a command line. On Windows, npx.cmd
// and vercel.cmd run through cmd.exe, which changes ^ & | < > % in an argument without a word:
// hello@anidealab.com's password reached Vercel changed that way (30 Oct 2026). This runs the Vercel
// CLI's own JavaScript with node and no shell, so the value arrives exactly, on any system.
//   PowerShell:  $env:ENV_VALUE = $key; node set-vercel-env.mjs <project> <NAME> [vercel@version]
// It links the project in a folder of its own, with the Vercel login already on the computer, and
// exits 0 once Vercel has the value. Deploy again afterwards so the site picks it up.
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const [project, name, cli = "vercel@65.2.0"] = process.argv.slice(2);
const value = process.env.ENV_VALUE;
if (!project || !name || !value) {
  console.error("Usage: ENV_VALUE=<the value> node set-vercel-env.mjs <project> <NAME> [vercel@version]");
  process.exit(2);
}
// the CLI doesn't need the value in its own environment; without telemetry it leaves nothing running
// in the work folder, which Windows won't delete while a process sits in it
const env = { ...process.env, VERCEL_TELEMETRY_DISABLED: "1" };
delete env.ENV_VALUE;

// The CLI, installed once per version under the temp folder. npm runs through a shell, but nothing
// secret goes to it.
const home = path.join(os.tmpdir(), "set-vercel-env", cli.replace(/[^\w.@-]/g, "_"));
const pkgFile = path.join(home, "node_modules", "vercel", "package.json");
if (!existsSync(pkgFile)) {
  spawnSync("npm", ["install", "--prefix", home, cli, "--no-audit", "--no-fund", "--loglevel=error"], { stdio: "inherit", shell: true, env });
  if (!existsSync(pkgFile)) {
    console.error(`Couldn't install ${cli}.`);
    process.exit(1);
  }
}
const pkg = JSON.parse(readFileSync(pkgFile, "utf8"));
const vercel = path.join(home, "node_modules", "vercel", typeof pkg.bin === "string" ? pkg.bin : pkg.bin.vercel);

const work = mkdtempSync(path.join(os.tmpdir(), "set-vercel-env-"));
const run = (...args) => spawnSync(process.execPath, [vercel, ...args], { cwd: work, env, stdio: ["ignore", "inherit", "inherit"] }).status;
let code = 1;
try {
  if (run("link", "--yes", "--project", project) !== 0) throw new Error(`Couldn't link the Vercel project ${project}.`);
  run("env", "rm", name, "production", "--yes"); // fails when it isn't there yet, which is fine
  // --value=... rather than --value ..., so a value starting with - isn't taken for a flag
  if (run("env", "add", name, "production", `--value=${value}`, "--yes") !== 0) throw new Error(`Vercel didn't take ${name}.`);
  console.log(`${name} is set in ${project}'s production settings. Deploy again so the site picks it up.`);
  code = 0;
} catch (e) {
  console.error(e.message);
} finally {
  // The link pulls the project's development settings into this folder, so it goes. On Windows a
  // file can stay held for a moment, so it retries, and a folder it still can't delete never counts
  // as Vercel refusing the value: on 30 Oct 2026 that stopped the setup script after Vercel took it.
  try {
    rmSync(work, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
  } catch (e) {
    console.error(`Couldn't delete ${work} (${e.code || e.message}): delete it by hand, since it holds the project's development settings.`);
  }
}
process.exit(code);
