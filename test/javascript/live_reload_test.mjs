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

    const lines = [
      [{text: "** (CompileError) cannot compile module MyApp", tone: "banner"}],
      [
        {text: "  3 │ ", tone: "chrome"},
        {text: "    foo()", tone: "body"},
      ],
    ];

    LiveReload.showErrorOverlay(lines);

    sinon.assert.calledOnceWithExactly(showStub, {
      content: lines,
      heading: "Compilation Error",
      id: OVERLAY_ID,
    });

    showStub.restore();
  });
});
