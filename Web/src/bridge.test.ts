import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { isRepositoryPath, parseNativeMessage } from "./bridge.ts";

const repository = { name: "demo", branch: "main", remote: null };
const listing = { files: [["src/a.ts", 12]], symlinks: ["link.ts"], unreadableDirectories: 0 };

describe("parseNativeMessage", () => {
  it("accepts the messages the app sends", () => {
    assert.deepEqual(parseNativeMessage({ type: "analysis.begin", run: 1, fresh: true, repository, listing }), {
      type: "analysis.begin",
      run: 1,
      fresh: true,
      repository,
      listing: { files: [{ path: "src/a.ts", size: 12 }], symlinks: ["link.ts"], unreadableDirectories: 0 },
    });
    assert.ok(parseNativeMessage({ type: "analysis.configs", run: 2, files: [["tsconfig.json", "{}"]] }));
    assert.ok(
      parseNativeMessage({ type: "analysis.sources", run: 2, files: [["a.ts", ""]], skipped: [["b.ts", "not_utf8"]] }),
    );
    assert.ok(parseNativeMessage({ type: "analysis.finish", run: 2 }));
    assert.ok(parseNativeMessage({ type: "analysis.cancel", run: 2 }));
    assert.ok(parseNativeMessage({ type: "analysis.fail", run: 2, error: "resources_exceeded" }));
    assert.deepEqual(parseNativeMessage({ type: "workspace.focusSearch" }), { type: "workspace.focusSearch" });
    assert.deepEqual(parseNativeMessage({ type: "window.fullScreen", on: false }), { type: "window.fullScreen", on: false });
    assert.deepEqual(parseNativeMessage({ type: "window.fullScreen", on: true }), { type: "window.fullScreen", on: true });
  });

  it("rejects malformed messages", () => {
    const rejected: unknown[] = [
      null,
      "analysis.finish",
      [],
      { type: "analysis.unknown", run: 1 },
      { type: "analysis.finish" },
      { type: "analysis.finish", run: 0 },
      { type: "analysis.finish", run: 1.5 },
      { type: "analysis.finish", run: "1" },
      { type: "analysis.begin", run: 1, fresh: true, repository },
      { type: "analysis.begin", run: 1, fresh: "yes", repository, listing },
      { type: "analysis.begin", run: 1, fresh: true, repository: { name: "demo" }, listing },
      { type: "analysis.begin", run: 1, fresh: true, repository, listing: { ...listing, unreadableDirectories: -1 } },
      { type: "analysis.begin", run: 1, fresh: true, repository, listing: { ...listing, files: [["a.ts", -1]] } },
      { type: "analysis.begin", run: 1, fresh: true, repository, listing: { ...listing, files: [["../a.ts", 1]] } },
      { type: "analysis.begin", run: 1, fresh: true, repository, listing: { ...listing, symlinks: ["/etc/passwd"] } },
      { type: "analysis.sources", run: 1, files: [["a.ts", 1]], skipped: [] },
      { type: "analysis.sources", run: 1, files: [], skipped: [["a.ts", "gone"]] },
      { type: "analysis.sources", run: 1, files: [["a.ts"]], skipped: [] },
      { type: "analysis.configs", run: 1, files: {} },
      { type: "analysis.fail", run: 1, error: "root_unavailable " },
      { type: "workspace.showFAQ" },
      { type: "window.fullScreen" },
      { type: "window.fullScreen", on: 0 },
      { type: "window.fullScreen", on: "false" },
    ];
    for (const message of rejected) assert.equal(parseNativeMessage(message), null, JSON.stringify(message));
  });
});

describe("isRepositoryPath", () => {
  it("accepts relative paths with ordinary segments", () => {
    for (const path of ["a.ts", "src/a.ts", ".github/x.ts", "a b/c\\d.ts", "..a/b"]) assert.ok(isRepositoryPath(path), path);
  });

  it("rejects absolute, empty and parent segments", () => {
    for (const path of ["", "/a.ts", "a//b.ts", "a/./b.ts", "a/../b.ts", "..", "a/", "a\0b"]) {
      assert.equal(isRepositoryPath(path), false, path);
    }
  });
});
