// The part of upstream lib/discovery.ts that does not touch the file system.
// The native app lists the folder and reads the files this module asks for;
// selection, analysis and graph building are upstream's own functions, called
// in the same order and with the same inputs as discoverRepository.

import { selectConfigFiles, type ConfigFile } from "../../upstream/src/lib/analysis/config.ts";
import { analyzeModuleRelationships } from "../../upstream/src/lib/analysis/relationships.ts";
import type { DiscoveryResult, RepositoryIdentity, SkipCounts } from "../../upstream/src/lib/discovery.ts";
import { buildDependencyGraph } from "../../upstream/src/lib/graph/build.ts";
import { selectSourceFiles, sourceExtension, type FileEntry, type SkippedSource, type SourceCandidate, type SourceFile } from "../../upstream/src/lib/source-files.ts";
import { toRenderGraph } from "../../upstream/src/lib/visualization/payload.ts";

import { presentDesktopError } from "../errors.ts";

export type Listing = {
  // Every regular file outside ignored directories, sorted by path.
  files: FileEntry[];
  // Every symbolic link found; only those that look like source files count
  // as skipped, as in upstream's walk.
  symlinks: string[];
  unreadableDirectories: number;
};

export type ReadPlan = {
  sources: SourceCandidate[];
  configs: string[];
};

export type Planned =
  | { kind: "read"; plan: ReadPlan; skipped: SkippedSource[] }
  | { kind: "done"; result: DiscoveryResult };

export function planRead(listing: Listing, repository: RepositoryIdentity): Planned {
  const symlinks: SkippedSource[] = listing.symlinks
    .filter((path) => sourceExtension(path) !== null)
    .map((path) => ({ path, reason: "symlink" }));

  if (listing.files.length === 0 && symlinks.length === 0) {
    if (listing.unreadableDirectories > 0) {
      return { kind: "done", result: { status: "error", error: presentDesktopError("root_unavailable"), repository } };
    }
    return { kind: "done", result: { status: "empty", repository } };
  }

  const selection = selectSourceFiles(listing.files);
  const skipped = [...symlinks, ...selection.skipped];
  if (selection.candidates.length === 0) {
    return {
      kind: "done",
      result: { status: "unsupported", repository, ...skipSummary(skipped, 0, listing.unreadableDirectories) },
    };
  }

  return {
    kind: "read",
    plan: { sources: selection.candidates, configs: selectConfigFiles(listing.files).map((file) => file.path) },
    skipped,
  };
}

export type ReadSources = {
  files: SourceFile[];
  skipped: SkippedSource[];
  configs: ConfigFile[];
};

export type AnalysisProgress = { stage: "analysis" | "graph"; files: number };

export function analyzeRepository(
  listing: Listing,
  repository: RepositoryIdentity,
  selectionSkipped: SkippedSource[],
  read: ReadSources,
  onProgress: (progress: AnalysisProgress) => void = () => {},
): DiscoveryResult {
  onProgress({ stage: "analysis", files: read.files.length });
  const analysis = analyzeModuleRelationships(read.files, {
    configFiles: read.configs,
    repositoryPaths: listing.files.map((file) => file.path),
  });
  onProgress({ stage: "graph", files: read.files.length });
  const graph = buildDependencyGraph(read.files, analysis.relationships);

  const skipped = skipSummary([...selectionSkipped, ...read.skipped], analysis.skipped.length, listing.unreadableDirectories);
  if (graph.nodes.length === 0) {
    return { status: "unsupported", repository, ...skipped };
  }

  return {
    status: "success",
    repository: { ...repository, fileCount: listing.files.length },
    ...skipped,
    graph: toRenderGraph(graph),
  };
}

export function skipSummary(files: SkippedSource[], parseFailed: number, unreadableDirectories: number) {
  const skipped: SkipCounts = { tooLarge: 0, symlinks: 0, unreadable: 0, parseFailed, unreadableDirectories };
  for (const { reason } of files) {
    if (reason === "too_large") skipped.tooLarge++;
    else if (reason === "symlink") skipped.symlinks++;
    else skipped.unreadable++;
  }
  const skippedCount = skipped.tooLarge + skipped.symlinks + skipped.unreadable + parseFailed + unreadableDirectories;
  return { skipped, skippedCount };
}
