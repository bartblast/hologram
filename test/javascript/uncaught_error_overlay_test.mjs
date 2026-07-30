"use strict";

import {defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import ErrorOverlay from "../../assets/js/error_overlay.mjs";
import UncaughtErrorOverlay from "../../assets/js/uncaught_error_overlay.mjs";

defineRuntimeGlobals();

const OVERLAY_ID = "hologram-uncaught-error-overlay";

describe("UncaughtErrorOverlay", () => {
  it("hide()", () => {
    const hideStub = sinon.stub(ErrorOverlay, "hide");

    UncaughtErrorOverlay.hide();

    sinon.assert.calledOnceWithExactly(hideStub, OVERLAY_ID);

    hideStub.restore();
  });

  it("show()", () => {
    const showStub = sinon.stub(ErrorOverlay, "show");

    UncaughtErrorOverlay.show("my content");

    sinon.assert.calledOnceWithExactly(showStub, {
      content: "my content",
      dismissable: true,
      heading: "Runtime Error",
      id: OVERLAY_ID,
    });

    showStub.restore();
  });
});
