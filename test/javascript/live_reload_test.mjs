"use strict";

import {defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import ErrorOverlay from "../../assets/js/error_overlay.mjs";
import LiveReload from "../../assets/js/live_reload.mjs";

defineRuntimeGlobals();

const OVERLAY_ID = "hologram-live-reload-error-overlay";

describe("LiveReload", () => {
  it("reload()", () => {
    const originalDocument = globalThis.document;
    const reloadSpy = sinon.spy();

    globalThis.document = {location: {reload: reloadSpy}};

    LiveReload.reload();

    sinon.assert.calledOnce(reloadSpy);

    globalThis.document = originalDocument;
  });

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
