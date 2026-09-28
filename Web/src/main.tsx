import { createRoot } from "react-dom/client";

import { App } from "./app.tsx";
import { parseNativeMessage, postToNative } from "./bridge.ts";
import { HostController } from "./controller.ts";
import { installNativeFullScreen } from "./fullscreen.ts";

const controller = new HostController();
const fullScreen = installNativeFullScreen(document, (on) => postToNative({ type: "fullScreen", on }));

declare global {
  interface Window {
    codefield: { receive(message: unknown): Promise<unknown> };
  }
}

window.codefield = {
  receive(message) {
    const parsed = parseNativeMessage(message);
    if (parsed === null) return Promise.reject(new Error("Malformed message."));
    if (parsed.type === "window.fullScreen") {
      fullScreen.windowChanged(parsed.on);
      return Promise.resolve(null);
    }
    return controller.receive(parsed);
  },
};

createRoot(document.getElementById("root")!).render(<App controller={controller} />);
postToNative({ type: "ready" });
