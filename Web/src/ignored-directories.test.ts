import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";

import { isIgnoredDirectoryName } from "../upstream/src/lib/source-files.ts";

const upstream = join(import.meta.dirname, "..", "upstream", "src", "lib", "source-files.ts");
const swift = join(import.meta.dirname, "..", "..", "Codefield", "Codefield", "Analysis", "RepositoryWalker.swift");

function quotedNames(block: string): string[] {
  return [...block.matchAll(/"([^"]+)"/g)].map((match) => match[1]).sort();
}

// The app's walk skips these directories before the page sees any path, so a
// name the app skipped that upstream does not would hide real source files.
describe("ignored directories", () => {
  it("are the same in the app's walk and in upstream", async () => {
    const upstreamBlock = (await readFile(upstream, "utf8")).match(/const IGNORED_DIRECTORIES = new Set\(\[([\s\S]*?)\]\);/)![1];
    const swiftBlock = (await readFile(swift, "utf8")).match(/static let names: Set<String> = \[([\s\S]*?)\]/)![1];

    const upstreamNames = quotedNames(upstreamBlock.replace(/\/\/.*$/gm, ""));
    const swiftNames = quotedNames(swiftBlock);
    assert.deepEqual(swiftNames, upstreamNames);
    for (const name of swiftNames) assert.ok(isIgnoredDirectoryName(name), name);
    assert.ok(isIgnoredDirectoryName("demo.egg-info"));
  });
});
