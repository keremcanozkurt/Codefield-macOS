import type { DiscoveryResult, RepositoryIdentity, SuccessResult } from "../upstream/src/lib/discovery.ts";
import { AnalysisWorker } from "./analysis/client.ts";
import { postToNative, type BeginReply, type NativeMessage, type Outcome } from "./bridge.ts";
import { presentDesktopError } from "./errors.ts";

// While an analysis runs, the last successful one stays on screen, so the
// workspace keeps its view, selection and filters through Analyze Again. A
// different repository starts a new session instead.
export type HostState = {
  session: number;
  repository: RepositoryIdentity | null;
  loading: boolean;
  previous: SuccessResult | null;
  result: DiscoveryResult | null;
};

export type HostEvent = "focusSearch";

const INITIAL: HostState = { session: 0, repository: null, loading: false, previous: null, result: null };

export class HostController {
  private state = INITIAL;
  private listeners = new Set<() => void>();
  private eventListeners = new Set<(event: HostEvent) => void>();
  private run = 0;
  private worker: AnalysisWorker | null = null;

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  snapshot = () => this.state;

  onEvent(listener: (event: HostEvent) => void) {
    this.eventListeners.add(listener);
    return () => {
      this.eventListeners.delete(listener);
    };
  }

  // Full-screen changes go to NativeFullScreen instead.
  async receive(message: Exclude<NativeMessage, { type: "window.fullScreen" }>): Promise<BeginReply | Outcome | null> {
    switch (message.type) {
      case "workspace.focusSearch":
        this.emit("focusSearch");
        return null;
      case "analysis.begin":
        return this.begin(message);
    }

    if (message.run !== this.run) return null;
    switch (message.type) {
      case "analysis.configs":
        this.worker?.send({ type: "configs", files: message.files });
        return null;
      case "analysis.sources":
        this.worker?.send({ type: "sources", files: message.files, skipped: message.skipped });
        return null;
      case "analysis.finish":
        return this.finish(message.run);
      case "analysis.fail":
        return this.complete({ status: "error", error: presentDesktopError(message.error), repository: this.state.repository ?? undefined });
      case "analysis.cancel":
        this.stopWorker();
        this.update({ loading: false, result: this.state.previous });
        return { status: "cancelled" };
    }
  }

  private async begin(message: Extract<NativeMessage, { type: "analysis.begin" }>): Promise<BeginReply> {
    if (message.run <= this.run) return { outcome: { status: "cancelled" } };
    this.stopWorker();
    this.run = message.run;
    const run = message.run;

    const current = this.state;
    const previous = message.fresh ? null : current.result?.status === "success" ? current.result : current.previous;
    this.update({
      session: message.fresh ? current.session + 1 : current.session,
      repository: message.repository,
      loading: true,
      previous,
      result: null,
    });

    try {
      const worker = await AnalysisWorker.start();
      if (run !== this.run) {
        worker.terminate();
        return { outcome: { status: "cancelled" } };
      }
      this.worker = worker;
      const planned = await worker.begin(message.listing, message.repository);
      if (run !== this.run) return { outcome: { status: "cancelled" } };
      if ("result" in planned) return { outcome: this.complete(planned.result) };
      return { read: planned.read };
    } catch (error) {
      if (run !== this.run) return { outcome: { status: "cancelled" } };
      console.error("Could not start the analysis.", error);
      return { outcome: this.complete({ status: "error", error: presentDesktopError("failed"), repository: message.repository }) };
    }
  }

  private async finish(run: number): Promise<Outcome> {
    const worker = this.worker;
    if (worker === null) return { status: "cancelled" };
    let result: DiscoveryResult;
    try {
      result = await worker.finish((progress) => postToNative({ type: "progress", run, stage: progress.stage }));
    } catch {
      if (run !== this.run) return { status: "cancelled" };
      result = { status: "error", error: presentDesktopError("failed"), repository: this.state.repository ?? undefined };
    }
    if (run !== this.run) return { status: "cancelled" };

    postToNative({ type: "progress", run, stage: "render" });
    const outcome = this.complete(result);
    await nextPaint();
    return outcome;
  }

  private complete(result: DiscoveryResult): Outcome {
    this.stopWorker();
    this.update({ loading: false, result });
    return outcomeOf(result);
  }

  private stopWorker() {
    this.worker?.terminate();
    this.worker = null;
  }

  private update(change: Partial<HostState>) {
    this.state = { ...this.state, ...change };
    for (const listener of this.listeners) listener();
  }

  private emit(event: HostEvent) {
    for (const listener of this.eventListeners) listener(event);
  }
}

export function outcomeOf(result: DiscoveryResult): Outcome {
  if (result.status === "success") return { status: "success", files: result.graph.nodes.length, edges: result.graph.edges.length };
  return { status: result.status };
}

// Two frames: React commits the result in the first, the browser paints it in
// the second. A hidden web view may not run animation frames at all.
function nextPaint(): Promise<void> {
  return new Promise((resolve) => {
    const timeout = setTimeout(resolve, 500);
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        clearTimeout(timeout);
        resolve();
      }),
    );
  });
}
