// Stands in for the native side in tests: lists and reads a folder with
// upstream's own Node file-system code, so the desktop pipeline can be checked
// against upstream's discoverRepository on the same folder.

import { readdir } from "node:fs/promises";
import { join } from "node:path";

import { selectConfigFiles } from "../../upstream/src/lib/analysis/config.ts";
import type { DiscoveryResult } from "../../upstream/src/lib/discovery.ts";
import { readConfigFiles, readSourceFiles } from "../../upstream/src/lib/local/read.ts";
import { describeRepository } from "../../upstream/src/lib/local/repository.ts";
import { listRepository } from "../../upstream/src/lib/local/walk.ts";
import { isIgnoredDirectoryName, type SkipReason, type SourceCandidate } from "../../upstream/src/lib/source-files.ts";
import type { Listing } from "./pipeline.ts";

export type NativeRead = {
  listing: Listing;
  repository: Awaited<ReturnType<typeof describeRepository>>;
  read(sources: string[], configs: string[]): Promise<{
    files: [string, string][];
    skipped: [string, SkipReason][];
    configs: [string, string][];
  }>;
};

export async function nativeRead(root: string): Promise<NativeRead> {
  const walked = await listRepository(root);
  const listing: Listing = {
    files: walked.files,
    // The app reports every link, upstream's walk only those that look like
    // source files; the pipeline has to cope with the difference.
    symlinks: await allSymlinks(root),
    unreadableDirectories: walked.unreadableDirectories,
  };
  return {
    listing,
    repository: await describeRepository(root),
    async read(sources, configs) {
      const bySource = new Map(listing.files.map((file) => [file.path, file]));
      // Only the path and size matter for reading.
      const candidates = sources.map((path) => ({ path, size: bySource.get(path)!.size }) as SourceCandidate);
      const read = await readSourceFiles(root, candidates);
      if (!read.ok) throw new Error("resources exceeded");
      const configFiles = await readConfigFiles(
        root,
        selectConfigFiles(listing.files).filter((file) => configs.includes(file.path)),
      );
      return {
        files: read.files.map((file) => [file.path, file.content]),
        skipped: read.skipped.map((file) => [file.path, file.reason]),
        configs: configFiles.map((file) => [file.path, file.content]),
      };
    },
  };
}

export function comparable(result: DiscoveryResult): unknown {
  return JSON.parse(JSON.stringify(result));
}

async function allSymlinks(root: string, relative = ""): Promise<string[]> {
  const links: string[] = [];
  for (const entry of await readdir(join(root, relative), { withFileTypes: true })) {
    const path = relative === "" ? entry.name : `${relative}/${entry.name}`;
    if (entry.isSymbolicLink()) links.push(path);
    else if (entry.isDirectory() && !isIgnoredDirectoryName(entry.name)) links.push(...(await allSymlinks(root, path)));
  }
  return links.sort();
}
