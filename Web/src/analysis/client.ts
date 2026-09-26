import type { DiscoveryResult, RepositoryIdentity } from "../../upstream/src/lib/discovery.ts";
import type { AnalysisProgress, Listing } from "./pipeline.ts";
import type { FromWorker, ToWorker } from "./protocol.ts";

type Planned = { read: { sources: string[]; configs: string[] } } | { result: DiscoveryResult };

let workerUrl: Promise<string> | null = null;

// The worker is started from a blob of its script rather than from its
// codefield: URL, so starting it depends only on fetch() through the app's
// scheme handler, not on how WebKit loads worker scripts from custom
// schemes. A blob worker shares the page's origin.
function scriptUrl(): Promise<string> {
  workerUrl ??= fetch("analysis-worker.js")
    .then((response) => {
      if (!response.ok) throw new Error(`analysis-worker.js: ${response.status}`);
      return response.blob();
    })
    .then((blob) => URL.createObjectURL(new Blob([blob], { type: "text/javascript" })))
    .catch((error: unknown) => {
      workerUrl = null;
      throw error;
    });
  return workerUrl;
}

export class AnalysisWorker {
  private readonly worker: Worker;
  private waiting: ((message: FromWorker) => void) | null = null;
  private onProgress: (progress: AnalysisProgress) => void = () => {};
  private failure: ((error: Error) => void) | null = null;

  private constructor(worker: Worker) {
    this.worker = worker;
    worker.onmessage = (event: MessageEvent<FromWorker>) => {
      if (event.data.type === "progress") this.onProgress(event.data.progress);
      else this.waiting?.(event.data);
    };
    worker.onerror = (event) => {
      event.preventDefault();
      this.failure?.(new Error("The analysis worker stopped."));
    };
  }

  static async start(): Promise<AnalysisWorker> {
    return new AnalysisWorker(new Worker(await scriptUrl()));
  }

  async begin(listing: Listing, repository: RepositoryIdentity): Promise<Planned> {
    const reply = await this.request({ type: "begin", listing, repository });
    return reply.type === "planned" ? { read: reply.read } : { result: (reply as Extract<FromWorker, { type: "result" }>).result };
  }

  send(message: Extract<ToWorker, { type: "configs" | "sources" }>): void {
    this.worker.postMessage(message);
  }

  async finish(onProgress: (progress: AnalysisProgress) => void): Promise<DiscoveryResult> {
    this.onProgress = onProgress;
    const reply = await this.request({ type: "finish" });
    if (reply.type !== "result") throw new Error("Unexpected reply from the analysis worker.");
    return reply.result;
  }

  terminate(): void {
    this.worker.terminate();
    this.failure?.(new Error("Cancelled."));
  }

  private request(message: ToWorker): Promise<FromWorker> {
    return new Promise((resolve, reject) => {
      this.waiting = (reply) => {
        this.waiting = null;
        this.failure = null;
        resolve(reply);
      };
      this.failure = (error) => {
        this.waiting = null;
        this.failure = null;
        reject(error);
      };
      this.worker.postMessage(message);
    });
  }
}
