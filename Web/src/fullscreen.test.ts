import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { NativeFullScreen } from "./fullscreen.ts";

function setUp() {
  const posted: boolean[] = [];
  const events = new EventTarget();
  let changes = 0;
  events.addEventListener("fullscreenchange", () => changes++);
  const fullScreen = new NativeFullScreen((on) => posted.push(on), events);
  const element = {} as Element;
  return { posted, fullScreen, element, changes: () => changes };
}

describe("NativeFullScreen", () => {
  it("asks the window to enter and leave full screen", async () => {
    const { posted, fullScreen, element, changes } = setUp();

    await fullScreen.request(element);
    assert.equal(fullScreen.fullscreenElement, element);
    await fullScreen.exit();
    assert.equal(fullScreen.fullscreenElement, null);
    fullScreen.windowChanged(false);

    assert.deepEqual(posted, [true, false]);
    assert.equal(changes(), 0);
  });

  it("reports the window leaving full screen on its own", async () => {
    const { posted, fullScreen, element, changes } = setUp();

    await fullScreen.request(element);
    fullScreen.windowChanged(true);
    assert.equal(changes(), 0);
    fullScreen.windowChanged(false);

    assert.equal(fullScreen.fullscreenElement, null);
    assert.equal(changes(), 1);
    assert.deepEqual(posted, [true]);
  });

  it("ignores the window's own full screen when the workspace did not ask for it", () => {
    const { fullScreen, changes } = setUp();

    fullScreen.windowChanged(true);
    fullScreen.windowChanged(false);

    assert.equal(fullScreen.fullscreenElement, null);
    assert.equal(changes(), 0);
  });

  it("can enter again after leaving", async () => {
    const { posted, fullScreen, element } = setUp();

    await fullScreen.request(element);
    fullScreen.windowChanged(false);
    await fullScreen.request(element);

    assert.equal(fullScreen.fullscreenElement, element);
    assert.deepEqual(posted, [true, true]);
  });
});
