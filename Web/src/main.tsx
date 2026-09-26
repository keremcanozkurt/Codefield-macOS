import { createRoot } from "react-dom/client";

import { App } from "./app.tsx";
import { parseNativeMessage, postToNative } from "./bridge.ts";
import { HostController } from "./controller.ts";

// The app leaves WebKit's element full screen off, so the workspace's full
// screen is its in-page layout and native full screen stays with the window.
// Without the Fullscreen API, document.fullscreenElement is undefined rather
// than null, and upstream's Workspace would then call the missing
// exitFullscreen when leaving its full screen.
if (!("fullscreenElement" in document)) {
  Object.defineProperty(document, "fullscreenElement", { get: () => null });
  Object.defineProperty(document, "exitFullscreen", { value: () => Promise.resolve() });
}

const controller = new HostController();

declare global {
  interface Window {
    codefield: { receive(message: unknown): Promise<unknown> };
  }
}

window.codefield = {
  receive(message) {
    const parsed = parseNativeMessage(message);
    if (parsed === null) return Promise.reject(new Error("Malformed message."));
    return controller.receive(parsed);
  },
};

createRoot(document.getElementById("root")!).render(<App controller={controller} />);
postToNative({ type: "ready" });
