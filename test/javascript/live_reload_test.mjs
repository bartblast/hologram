"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  JSDOM,
  registerWebApis,
} from "./support/helpers.mjs";

import LiveReload from "../../assets/js/live_reload.mjs";

defineGlobalErlangAndElixirModules();
registerWebApis();

describe("LiveReload", () => {
  beforeEach(() => {
    const {window} = new JSDOM("<!DOCTYPE html><html><body></body></html>");
    globalThis.document = window.document;
  });

  afterEach(() => {
    delete globalThis.document;
  });

  describe("showErrorOverlay()", () => {
    it("creates and displays error overlay with content", () => {
      const content = "Test error message";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(overlay);
      assert.equal(overlay.textContent, content);
      assert.equal(overlay.tagName, "DIV");
      assert.isTrue(document.body.contains(overlay));
    });

    it("applies correct styling to the overlay", () => {
      const content = "Style test message";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      const style = overlay.style;

      // Critical positioning and overlay behavior
      assert.equal(style.position, "fixed");
      assert.equal(style.top, "0px");
      assert.equal(style.left, "0px");
      assert.equal(style.width, "100vw");
      assert.equal(style.height, "100vh");
      assert.equal(style.zIndex, "2147483647");

      // Key visibility styles
      assert.equal(style.backgroundColor, "black");
      assert.equal(style.color, "white");
      assert.equal(style.whiteSpace, "pre-wrap");
    });

    it("removes existing overlay before creating new one", () => {
      const firstContent = "First error message";
      const secondContent = "Second error message";

      LiveReload.showErrorOverlay(firstContent);

      const firstOverlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(firstOverlay);
      assert.equal(firstOverlay.textContent, firstContent);

      LiveReload.showErrorOverlay(secondContent);

      const secondOverlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(secondOverlay);
      assert.equal(secondOverlay.textContent, secondContent);

      assert.isFalse(document.body.contains(firstOverlay));
      assert.notEqual(secondOverlay, firstOverlay);
    });

    it("handles empty content", () => {
      const content = "";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(overlay);
      assert.equal(overlay.textContent, "");
      assert.isTrue(document.body.contains(overlay));
    });

    it("handles multiline content", () => {
      const content = "Line 1\nLine 2\nLine 3";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(overlay);
      assert.equal(overlay.textContent, content);
      assert.isTrue(document.body.contains(overlay));
      assert.equal(overlay.style.whiteSpace, "pre-wrap");
    });
  });
});
