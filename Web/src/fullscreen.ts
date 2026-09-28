// The app leaves WebKit's element full screen off (a web view's element full
// screen opens a window of its own), so the page has no Fullscreen API.
// These stand-ins let upstream's Full screen button put the app window itself
// into macOS full screen, and report leaving it the way a browser reports
// leaving real full screen: fullscreenElement becomes null and
// "fullscreenchange" fires, so the workspace ends its full-screen layout
// whether the window left through the button, Escape, the green button, the
// View menu or ⌃⌘F.
export class NativeFullScreen {
  private element: Element | null = null;
  private readonly post: (on: boolean) => void;
  private readonly events: EventTarget;

  constructor(post: (on: boolean) => void, events: EventTarget) {
    this.post = post;
    this.events = events;
  }

  get fullscreenElement(): Element | null {
    return this.element;
  }

  request(element: Element): Promise<void> {
    this.element = element;
    this.post(true);
    return Promise.resolve();
  }

  // Cleared right away rather than when the window reports back, since the
  // window may not have been in full screen to leave.
  exit(): Promise<void> {
    this.element = null;
    this.post(false);
    return Promise.resolve();
  }

  windowChanged(on: boolean): void {
    if (on || this.element === null) return;
    this.element = null;
    this.events.dispatchEvent(new Event("fullscreenchange"));
  }
}

export function installNativeFullScreen(document: Document, post: (on: boolean) => void): NativeFullScreen {
  const fullScreen = new NativeFullScreen(post, document);
  Object.defineProperty(document, "fullscreenElement", { configurable: true, get: () => fullScreen.fullscreenElement });
  Object.defineProperty(document, "exitFullscreen", { configurable: true, value: () => fullScreen.exit() });
  Object.defineProperty(Element.prototype, "requestFullscreen", {
    configurable: true,
    value(this: Element) {
      return fullScreen.request(this);
    },
  });
  return fullScreen;
}
