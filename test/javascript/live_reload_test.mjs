"use strict";

import {defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import ErrorOverlay from "../../assets/js/error_overlay.mjs";
import LiveReload from "../../assets/js/live_reload.mjs";

defineRuntimeGlobals();

const OVERLAY_ID = "hologram-live-reload-error-overlay";

describe("LiveReload", () => {
  it("showErrorOverlay()", () => {
    const showStub = sinon.stub(ErrorOverlay, "show");

    LiveReload.showErrorOverlay("my content");

    sinon.assert.calledOnceWithExactly(showStub, {
      content: "my content",
      heading: "Compilation Error",
      id: OVERLAY_ID,
    });

    showStub.restore();
  });
});
