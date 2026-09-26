import type { DiscoveryResult, RepositoryIdentity } from "../../upstream/src/lib/discovery.ts";
import type { SkipReason } from "../../upstream/src/lib/source-files.ts";
import type { AnalysisProgress, Listing } from "./pipeline.ts";

export type ToWorker =
  | { type: "begin"; listing: Listing; repository: RepositoryIdentity }
  | { type: "configs"; files: [string, string][] }
  | { type: "sources"; files: [string, string][]; skipped: [string, SkipReason][] }
  | { type: "finish" };

export type FromWorker =
  | { type: "planned"; read: { sources: string[]; configs: string[] } }
  | { type: "result"; result: DiscoveryResult }
  | { type: "progress"; progress: AnalysisProgress };
