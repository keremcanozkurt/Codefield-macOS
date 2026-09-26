import { useEffect, useRef, useSyncExternalStore } from "react";

import { DiscoveryNotice } from "@/components/discovery-notice";
import { Workspace } from "@/components/workspace";
import type { SkipCounts } from "@/lib/discovery";
import { EMPTY_REPOSITORY, NO_READABLE_SOURCE_FILES, NO_SUPPORTED_SOURCE_FILES } from "@/lib/errors/presentation";

import { postToNative } from "./bridge.ts";
import type { HostController } from "./controller.ts";
import { FaqDialog } from "./faq-dialog.tsx";

export function App({ controller }: { controller: HostController }) {
  const state = useSyncExternalStore(controller.subscribe, controller.snapshot);
  const faqRef = useRef<HTMLDialogElement>(null);

  useEffect(
    () =>
      controller.onEvent((event) => {
        if (event === "showFAQ") {
          if (!faqRef.current?.open) faqRef.current?.showModal();
        } else {
          // Upstream's search field is the workspace's only combobox.
          document.querySelector<HTMLInputElement>('input[role="combobox"]')?.focus();
        }
      }),
    [controller],
  );

  const { repository, result, loading } = state;
  const shown = result?.status === "success" ? result : loading ? state.previous : null;

  return (
    <>
      <main className="flex h-full min-h-0 flex-col px-4 pt-3" aria-busy={loading}>
        {shown !== null && repository !== null && (
          <div className="desktop-workspace">
            <Workspace
              key={state.session}
              graph={shown.graph}
              label={`Dependency graph of ${repository.name}: ${formatCount(shown.graph.nodes.length, "file", "files")}, ${formatCount(shown.graph.edges.length, "edge", "edges")}`}
              repositoryName={repository.name}
            />
          </div>
        )}

        {result !== null && result.status !== "success" && (
          <div className="m-auto w-full max-w-xl pb-16">
            {result.status === "empty" && (
              <DiscoveryNotice tone="warning" title={EMPTY_REPOSITORY.title} message={EMPTY_REPOSITORY.message} />
            )}
            {result.status === "unsupported" &&
              (result.skippedCount > 0 ? (
                <DiscoveryNotice
                  tone="warning"
                  title={NO_READABLE_SOURCE_FILES.title}
                  message={NO_READABLE_SOURCE_FILES.message}
                  detail={skipSummary(result.skipped)}
                />
              ) : (
                <DiscoveryNotice
                  tone="warning"
                  title={NO_SUPPORTED_SOURCE_FILES.title}
                  message={NO_SUPPORTED_SOURCE_FILES.message}
                  detail={NO_SUPPORTED_SOURCE_FILES.detail}
                />
              ))}
            {result.status === "error" && (
              <DiscoveryNotice
                tone="error"
                title={result.error.title}
                message={result.error.message}
                retry={result.error.retryable ? { onClick: () => postToNative({ type: "analyzeAgain" }) } : undefined}
              />
            )}
          </div>
        )}

        <p aria-live="polite" className="flex h-8 shrink-0 items-center gap-3 text-xs text-subtle tabular-nums">
          {shown !== null && (
            <>
              <span className={`shrink-0 ${loading ? "opacity-60" : ""}`}>
                {formatCount(shown.graph.nodes.length, "source file", "source files")} ·{" "}
                {formatCount(shown.graph.edges.length, "edge", "edges")} ·{" "}
                {formatCount(shown.repository.fileCount, "file", "files")} in the folder
              </span>
              {shown.skippedCount > 0 && <span className="truncate">{skipSummary(shown.skipped)}</span>}
            </>
          )}
        </p>
      </main>
      <FaqDialog ref={faqRef} />
    </>
  );
}

function formatCount(count: number, singular: string, plural: string) {
  return `${count.toLocaleString("en-US")} ${count === 1 ? singular : plural}`;
}

function skipSummary(skipped: SkipCounts): string {
  const parts = [
    skipped.tooLarge > 0 && `${formatCount(skipped.tooLarge, "file", "files")} too large to analyze safely`,
    skipped.symlinks > 0 && `${formatCount(skipped.symlinks, "symbolic link", "symbolic links")} not followed`,
    skipped.unreadable > 0 && `${formatCount(skipped.unreadable, "file", "files")} not readable as UTF-8 text`,
    skipped.parseFailed > 0 && `${formatCount(skipped.parseFailed, "file", "files")} shown without relationships, as they could not be parsed`,
    skipped.unreadableDirectories > 0 &&
      `${formatCount(skipped.unreadableDirectories, "directory", "directories")} could not be read`,
  ].filter(Boolean);
  return parts.join(" · ");
}
