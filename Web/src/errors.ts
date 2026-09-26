import type { PresentedError } from "../upstream/src/lib/errors/presentation.ts";

// Upstream's copy for these errors points at the terminal Codefield was
// started from; the app has none.
export type DesktopErrorCode = "root_unavailable" | "resources_exceeded" | "failed";

const COPY: Record<DesktopErrorCode, PresentedError> = {
  root_unavailable: {
    title: "Folder unavailable",
    message: "The folder could not be read. It may have been moved, deleted, or its permissions changed.",
    retryable: true,
  },
  resources_exceeded: {
    title: "Repository too large to analyze",
    message: "The selected source files exceed the memory Codefield allows for one analysis.",
    retryable: false,
  },
  failed: {
    title: "Analysis failed",
    message: "Codefield could not analyze this folder.",
    retryable: true,
  },
};

export function presentDesktopError(code: DesktopErrorCode): PresentedError {
  return COPY[code];
}

export function isDesktopErrorCode(value: unknown): value is DesktopErrorCode {
  return typeof value === "string" && Object.hasOwn(COPY, value);
}
