// Builds the workspace page into the app's resources. The output is checked
// in, so building the app in Xcode does not need Node.
//
//   npm run build

import { execFileSync } from "node:child_process";
import { copyFile, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import * as esbuild from "esbuild";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = resolve(web, "..", "Codefield", "Codefield", "Resources", "Workspace");

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });

const shared = {
  bundle: true,
  format: "iife",
  platform: "browser",
  target: "safari18",
  minify: true,
  legalComments: "eof",
  define: { "process.env.NODE_ENV": '"production"' },
  tsconfig: join(web, "tsconfig.json"),
  logLevel: "warning",
};

const page = await esbuild.build({
  ...shared,
  entryPoints: { workspace: join(web, "src", "main.tsx") },
  outdir: output,
  metafile: true,
});

const worker = await esbuild.build({
  ...shared,
  entryPoints: { "analysis-worker": join(web, "src", "analysis", "worker.ts") },
  outdir: output,
  // TypeScript's compiler requires these only inside its Node host, which the
  // analyzers never create; in the worker the calls are never reached.
  external: ["fs", "path", "os", "crypto", "inspector", "perf_hooks", "source-map-support", "buffer", "module", "child_process", "worker_threads"],
  metafile: true,
});

await writeFile(join(output, "ThirdPartyLicenses.txt"), await licenses([page.metafile, worker.metafile]));

execFileSync(
  join(web, "node_modules", ".bin", "tailwindcss"),
  ["--input", join(web, "src", "workspace.css"), "--output", join(output, "workspace.css"), "--minify"],
  { cwd: web, stdio: ["ignore", "ignore", "inherit"] },
);

await copyFile(join(web, "src", "workspace.html"), join(output, "workspace.html"));

// The native FAQ window reads the same questions the page shows.
const product = await import(pathToFileURL(join(web, "src", "product.ts")).href);
await writeFile(
  join(output, "faq.json"),
  `${JSON.stringify({ supportURL: product.SUPPORT_URL, supportNote: product.SUPPORT_NOTE, entries: product.FAQ }, null, 2)}\n`,
);

// The license text of every npm package that ended up in the bundles.
async function licenses(metafiles) {
  const packages = new Set();
  for (const metafile of metafiles) {
    for (const input of Object.keys(metafile.inputs)) {
      const match = input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)\//);
      if (match) packages.add(match[1]);
    }
  }
  const sections = [];
  for (const name of [...packages].sort()) {
    const directory = join(web, "node_modules", name);
    const { version, license } = JSON.parse(await readFile(join(directory, "package.json"), "utf8"));
    const file = (await readdir(directory)).find((entry) => /^licen[cs]e/i.test(entry));
    const text = file === undefined ? `License: ${license}` : (await readFile(join(directory, file), "utf8")).trim();
    sections.push(`${name} ${version}\n\n${text}`);
  }
  return `${sections.join(`\n\n${"-".repeat(72)}\n\n`)}\n`;
}

console.log(`Built ${(await readdir(output)).sort().join(", ")} into ${output}`);
