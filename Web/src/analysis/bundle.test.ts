import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { createContext, runInContext } from "node:vm";

import { discoverRepository } from "../../upstream/src/lib/discovery.ts";
import { temporaryDirectory } from "../../upstream/src/lib/local/testing.ts";
import { FIXTURES } from "./fixtures.ts";
import type { FromWorker, ToWorker } from "./protocol.ts";
import { comparable, nativeRead } from "./testing.ts";

const BUNDLE = join(import.meta.dirname, "..", "..", "..", "Codefield", "Codefield", "Resources", "Workspace", "analysis-worker.js");

// Runs the built worker script in a bare context: no require, no process, no
// Node globals, as in a web worker. Messages go through structuredClone, as
// they would through postMessage.
async function loadWorker() {
  const replies: FromWorker[] = [];
  const self: { onmessage: ((event: { data: ToWorker }) => void) | null; postMessage(message: FromWorker): void } = {
    onmessage: null,
    postMessage: (message) => replies.push(structuredClone(message)),
  };
  const context = createContext({ self, console, TextEncoder, TextDecoder, URL, structuredClone });
  runInContext(await readFile(BUNDLE, "utf8"), context);
  return {
    send(message: ToWorker) {
      self.onmessage!({ data: structuredClone(message) });
      return replies.splice(0);
    },
  };
}

describe("built analysis worker", { skip: !existsSync(BUNDLE) && "run npm run build first" }, () => {
  for (const fixture of FIXTURES) {
    it(`matches upstream discovery for ${fixture.name}`, async () => {
      const directory = await temporaryDirectory();
      try {
        await fixture.create(directory.path);
        const native = await nativeRead(directory.path);
        const worker = await loadWorker();

        let replies = worker.send({ type: "begin", listing: native.listing, repository: native.repository });
        const planned = replies.at(-1)!;
        if (planned.type === "planned") {
          const read = await native.read(planned.read.sources, planned.read.configs);
          worker.send({ type: "configs", files: read.configs });
          // Split in two to cover batches arriving separately.
          const half = Math.ceil(read.files.length / 2);
          worker.send({ type: "sources", files: read.files.slice(half), skipped: [] });
          worker.send({ type: "sources", files: read.files.slice(0, half), skipped: read.skipped });
          replies = worker.send({ type: "finish" });
        }

        const result = replies.at(-1);
        assert.equal(result?.type, "result");
        if (result?.type !== "result") return;
        assert.deepEqual(comparable(result.result), comparable(await discoverRepository(directory.path)));
      } finally {
        await directory.remove();
      }
    });
  }
});
