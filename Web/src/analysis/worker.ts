import type { ConfigFile } from "../../upstream/src/lib/analysis/config.ts";
import type { RepositoryIdentity } from "../../upstream/src/lib/discovery.ts";
import type { SkippedSource, SourceCandidate, SourceFile } from "../../upstream/src/lib/source-files.ts";
import { presentDesktopError } from "../errors.ts";
import { analyzeRepository, planRead, type Listing } from "./pipeline.ts";
import type { FromWorker, ToWorker } from "./protocol.ts";

// One worker serves one analysis and is terminated afterwards, which also
// releases the source text it held.

type State = {
  listing: Listing;
  repository: RepositoryIdentity;
  selectionSkipped: SkippedSource[];
  candidates: Map<string, SourceCandidate>;
  configPaths: Set<string>;
  contents: Map<string, string>;
  skipped: Map<string, SkippedSource>;
  configs: ConfigFile[];
};

type WorkerScope = {
  postMessage(message: FromWorker): void;
  onmessage: ((event: MessageEvent<ToWorker>) => void) | null;
};

const scope = self as unknown as WorkerScope;
const post = (message: FromWorker) => scope.postMessage(message);

let state: State | null = null;
let repository: RepositoryIdentity | undefined;

scope.onmessage = (event) => {
  const message = event.data;
  try {
    handle(message);
  } catch (error) {
    console.error("Analysis failed.", error instanceof Error ? error.name : "unknown error");
    post({ type: "result", result: { status: "error", error: presentDesktopError("failed"), repository } });
  }
};

function handle(message: ToWorker) {
  if (message.type === "begin") {
    repository = message.repository;
    const planned = planRead(message.listing, message.repository);
    if (planned.kind === "done") {
      post({ type: "result", result: planned.result });
      return;
    }
    state = {
      listing: message.listing,
      repository: message.repository,
      selectionSkipped: planned.skipped,
      candidates: new Map(planned.plan.sources.map((candidate) => [candidate.path, candidate])),
      configPaths: new Set(planned.plan.configs),
      contents: new Map(),
      skipped: new Map(),
      configs: [],
    };
    post({ type: "planned", read: { sources: planned.plan.sources.map((file) => file.path), configs: planned.plan.configs } });
    return;
  }

  if (state === null) return;
  const current = state;

  // Only files from the plan are accepted, whatever the app sends.
  if (message.type === "configs") {
    for (const [path, content] of message.files) {
      if (current.configPaths.has(path)) current.configs.push({ path, content });
    }
  } else if (message.type === "sources") {
    for (const [path, content] of message.files) {
      if (current.candidates.has(path)) current.contents.set(path, content);
    }
    for (const [path, reason] of message.skipped) {
      if (current.candidates.has(path)) current.skipped.set(path, { path, reason });
    }
  } else if (message.type === "finish") {
    // Plan order, which is the order upstream reads files in, whatever order
    // the batches arrived in.
    const files: SourceFile[] = [];
    const skipped: SkippedSource[] = [];
    for (const candidate of current.candidates.values()) {
      const content = current.contents.get(candidate.path);
      if (content !== undefined) files.push({ ...candidate, content });
      else skipped.push(current.skipped.get(candidate.path) ?? { path: candidate.path, reason: "unreadable" });
    }
    const configs = [...current.configs].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
    state = null;

    const result = analyzeRepository(current.listing, current.repository, current.selectionSkipped, { files, skipped, configs }, (progress) =>
      post({ type: "progress", progress }),
    );
    post({ type: "result", result });
  }
}
