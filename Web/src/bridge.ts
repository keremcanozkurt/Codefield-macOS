// The message protocol between the native app and this page.
//
// Native to page: the app calls `window.codefield.receive(message)` through
// WKWebView.callAsyncJavaScript, which passes the message as a value rather
// than as source text, and awaits the returned promise for the reply.
//
// Page to native: `window.webkit.messageHandlers.codefield.postMessage`.
//
// Every analysis message carries the run number the app assigned; the page
// ignores messages for any run other than the current one, so a cancelled
// analysis can never overwrite a newer one.

import type { RepositoryIdentity } from "../upstream/src/lib/local/repository.ts";
import type { FileEntry, SkipReason } from "../upstream/src/lib/source-files.ts";
import type { Listing } from "./analysis/pipeline.ts";
import { isDesktopErrorCode, type DesktopErrorCode } from "./errors.ts";

export type NativeMessage =
  | { type: "analysis.begin"; run: number; fresh: boolean; repository: RepositoryIdentity; listing: Listing }
  | { type: "analysis.configs"; run: number; files: [path: string, content: string][] }
  | { type: "analysis.sources"; run: number; files: [path: string, content: string][]; skipped: [path: string, reason: SkipReason][] }
  | { type: "analysis.finish"; run: number }
  | { type: "analysis.fail"; run: number; error: DesktopErrorCode }
  | { type: "analysis.cancel"; run: number }
  | { type: "workspace.focusSearch" }
  // The window entered or left macOS full screen, by any means.
  | { type: "window.fullScreen"; on: boolean };

// Reply to analysis.begin: the files to read, or the finished outcome when
// the listing alone decides it (an empty folder, no supported files).
export type BeginReply = { read: { sources: string[]; configs: string[] } } | { outcome: Outcome };

// What the app shows about a finished analysis.
export type Outcome =
  | { status: "success"; files: number; edges: number }
  | { status: "empty" | "unsupported" | "error" | "cancelled" };

export type PageMessage =
  | { type: "ready" }
  | { type: "progress"; run: number; stage: "analysis" | "graph" | "render" }
  // The Retry button of an error notice.
  | { type: "analyzeAgain" }
  // The workspace's Full screen button: put the window in or out of macOS
  // full screen.
  | { type: "fullScreen"; on: boolean };

const SKIP_REASONS: readonly SkipReason[] = ["too_large", "not_utf8", "symlink", "unreadable"];

export function parseNativeMessage(value: unknown): NativeMessage | null {
  if (!isRecord(value) || typeof value.type !== "string") return null;
  if (value.type === "workspace.focusSearch") return { type: value.type };
  if (value.type === "window.fullScreen") {
    return typeof value.on === "boolean" ? { type: value.type, on: value.on } : null;
  }

  const run = value.run;
  if (!isRun(run)) return null;
  switch (value.type) {
    case "analysis.begin": {
      const repository = parseRepository(value.repository);
      const listing = parseListing(value.listing);
      if (repository === null || listing === null || typeof value.fresh !== "boolean") return null;
      return { type: "analysis.begin", run, fresh: value.fresh, repository, listing };
    }
    case "analysis.configs": {
      const files = parsePairs(value.files, isString);
      return files === null ? null : { type: "analysis.configs", run, files };
    }
    case "analysis.sources": {
      const files = parsePairs(value.files, isString);
      const skipped = parsePairs(value.skipped, isSkipReason);
      return files === null || skipped === null ? null : { type: "analysis.sources", run, files, skipped };
    }
    case "analysis.finish":
    case "analysis.cancel":
      return { type: value.type, run };
    case "analysis.fail":
      return isDesktopErrorCode(value.error) ? { type: "analysis.fail", run, error: value.error } : null;
    default:
      return null;
  }
}

function parseRepository(value: unknown): RepositoryIdentity | null {
  if (!isRecord(value) || !isString(value.name)) return null;
  if (!isNullableString(value.branch) || !isNullableString(value.remote)) return null;
  return { name: value.name, branch: value.branch, remote: value.remote };
}

function parseListing(value: unknown): Listing | null {
  if (!isRecord(value) || !Array.isArray(value.files) || !Array.isArray(value.symlinks)) return null;
  const unreadableDirectories = value.unreadableDirectories;
  if (typeof unreadableDirectories !== "number" || !Number.isInteger(unreadableDirectories) || unreadableDirectories < 0) {
    return null;
  }

  const files: FileEntry[] = [];
  for (const entry of value.files) {
    if (!Array.isArray(entry) || entry.length !== 2) return null;
    const [path, size] = entry;
    if (!isRepositoryPath(path) || typeof size !== "number" || !Number.isInteger(size) || size < 0) return null;
    files.push({ path, size });
  }
  if (!value.symlinks.every(isRepositoryPath)) return null;
  return { files, symlinks: value.symlinks, unreadableDirectories };
}

function parsePairs<T>(value: unknown, isSecond: (item: unknown) => item is T): [string, T][] | null {
  if (!Array.isArray(value)) return null;
  for (const entry of value) {
    if (!Array.isArray(entry) || entry.length !== 2 || !isRepositoryPath(entry[0]) || !isSecond(entry[1])) return null;
  }
  return value as [string, T][];
}

// Repository-relative, "/"-separated, with no empty, "." or ".." segments:
// the same shape upstream's graph builder insists on.
export function isRepositoryPath(value: unknown): value is string {
  if (typeof value !== "string" || value === "" || value.includes("\0")) return false;
  return value.split("/").every((segment) => segment !== "" && segment !== "." && segment !== "..");
}

function isRun(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isSkipReason(value: unknown): value is SkipReason {
  return typeof value === "string" && (SKIP_REASONS as readonly string[]).includes(value);
}

type MessageHandler = { postMessage(message: PageMessage): void };

export function postToNative(message: PageMessage): void {
  const handler = (window as { webkit?: { messageHandlers?: { codefield?: MessageHandler } } }).webkit?.messageHandlers
    ?.codefield;
  handler?.postMessage(message);
}
