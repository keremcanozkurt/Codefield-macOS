// Copies the parts of Codefield that the macOS workspace shares into
// upstream/, unchanged. The Codefield checkout is only read: files are copied
// out of it and `git rev-parse` runs without optional locks, so not even the
// index is refreshed.
//
//   npm run sync [-- path/to/Codefield]

import { execFileSync } from "node:child_process";
import { cp, mkdir, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const target = join(web, "upstream");

let source;
try {
  source = await realpath(resolve(process.argv[2] ?? join(web, "..", "..", "Codefield")));
  const { name } = JSON.parse(await readFile(join(source, "package.json"), "utf8"));
  if (name !== "@keremcanozkurt/codefield") throw new Error(`package.json names ${name}`);
} catch (error) {
  console.error(`Not a Codefield checkout: ${process.argv[2] ?? "../../Codefield"} (${error.message})`);
  process.exit(1);
}
// rm below only ever touches upstream/ in this repository.
if (source === web || source.startsWith(web + sep) || web.startsWith(source + sep)) {
  console.error("The Codefield checkout and this repository must be separate folders.");
  process.exit(1);
}

const COPIED = ["LICENSE", "src/lib", "src/components", "src/app/globals.css"];

// Server-only or command-line-only: the session token check of the local web
// server and the copyable shell command on its start page.
const EXCLUDED = new Set(["src/lib/local/session.ts", "src/lib/local/session.test.ts", "src/components/command-line.tsx"]);

await rm(target, { recursive: true, force: true });
for (const path of COPIED) {
  await mkdir(dirname(join(target, path)), { recursive: true });
  await cp(join(source, path), join(target, path), {
    recursive: true,
    filter: (from) => !EXCLUDED.has(relative(source, from).split("\\").join("/")),
  });
}

const git = (...args) => execFileSync("git", ["--no-optional-locks", "-C", source, ...args], { encoding: "utf8" }).trim();
const revision = git("rev-parse", "HEAD");
const dirty = git("status", "--porcelain", "--", ...COPIED) !== "";
await writeFile(join(target, "REVISION"), `${revision}${dirty ? " with uncommitted changes" : ""}\n`);

console.log(`Copied Codefield ${revision.slice(0, 7)}${dirty ? " (uncommitted changes)" : ""} into ${relative(process.cwd(), target) || "."}`);
