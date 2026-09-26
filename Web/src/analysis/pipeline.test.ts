import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { DiscoveryResult } from "../../upstream/src/lib/discovery.ts";
import { discoverRepository } from "../../upstream/src/lib/discovery.ts";
import { temporaryDirectory } from "../../upstream/src/lib/local/testing.ts";
import { FIXTURES } from "./fixtures.ts";
import { analyzeRepository, planRead } from "./pipeline.ts";
import { comparable, nativeRead } from "./testing.ts";

async function desktopDiscovery(root: string): Promise<DiscoveryResult> {
  const native = await nativeRead(root);
  const planned = planRead(native.listing, native.repository);
  if (planned.kind === "done") return planned.result;

  const read = await native.read(
    planned.plan.sources.map((file) => file.path),
    planned.plan.configs,
  );
  const contents = new Map(read.files);
  return analyzeRepository(native.listing, native.repository, planned.skipped, {
    files: planned.plan.sources
      .filter((file) => contents.has(file.path))
      .map((file) => ({ ...file, content: contents.get(file.path)! })),
    skipped: read.skipped.map(([path, reason]) => ({ path, reason })),
    configs: read.configs.map(([path, content]) => ({ path, content })),
  });
}

describe("desktop pipeline", () => {
  for (const fixture of FIXTURES) {
    it(`matches upstream discovery for ${fixture.name}`, async () => {
      const directory = await temporaryDirectory();
      try {
        await fixture.create(directory.path);
        assert.deepEqual(comparable(await desktopDiscovery(directory.path)), comparable(await discoverRepository(directory.path)));
      } finally {
        await directory.remove();
      }
    });
  }

  it("uses the app's copy for a folder that cannot be listed", () => {
    const planned = planRead({ files: [], symlinks: [], unreadableDirectories: 1 }, { name: "x", branch: null, remote: null });
    assert.equal(planned.kind, "done");
    if (planned.kind !== "done" || planned.result.status !== "error") return assert.fail();
    assert.ok(!planned.result.error.message.includes("terminal"));
  });

  it("counts only links that look like source files as skipped", () => {
    const planned = planRead(
      { files: [{ path: "a.ts", size: 1 }], symlinks: ["docs", "b.ts", "c.md"], unreadableDirectories: 0 },
      { name: "x", branch: null, remote: null },
    );
    assert.equal(planned.kind, "read");
    if (planned.kind !== "read") return;
    assert.deepEqual(planned.skipped, [{ path: "b.ts", reason: "symlink" }]);
  });
});
