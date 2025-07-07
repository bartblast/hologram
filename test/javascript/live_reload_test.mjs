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
    it("creates and displays error overlay", () => {
      const content = "Test error message";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(overlay);
      assert.equal(overlay.tagName, "DIV");
      assert.isTrue(document.body.contains(overlay));

      // Check DOM structure
      assert.equal(overlay.children.length, 2);
      assert.equal(overlay.children[0].tagName, "H1");
      assert.equal(overlay.children[1].tagName, "DIV");
    });

    it("creates h1 heading with correct text and styles", () => {
      const content = "Test error message";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      // Check h1 heading exists and has correct content
      const heading = overlay.children[0];
      assert.equal(heading.tagName, "H1");
      assert.equal(heading.textContent, "Compilation Error");

      // Check heading styles
      const style = heading.style;
      assert.equal(style.marginTop, "0px");
      assert.equal(style.marginBottom, "50px");
      assert.equal(style.fontSize, "36px");
      assert.equal(style.fontWeight, "700");
    });

    it("creates content container with correct content", () => {
      const content = "Test error message";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      // Check that content is in the content container
      const contentContainer = overlay.children[1];
      assert.equal(contentContainer.tagName, "DIV");
      assert.equal(contentContainer.textContent, content);
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
      assert.equal(firstOverlay.children[1].textContent, firstContent);

      LiveReload.showErrorOverlay(secondContent);

      const secondOverlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(secondOverlay);
      assert.equal(secondOverlay.children[1].textContent, secondContent);

      assert.isFalse(document.body.contains(firstOverlay));
      assert.notEqual(secondOverlay, firstOverlay);

      // Body scrolling should still be disabled
      assert.equal(document.body.style.overflow, "hidden");
    });

    it("handles empty content", () => {
      const content = "";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(overlay);
      assert.isTrue(document.body.contains(overlay));

      // Should have proper structure and content
      assert.equal(overlay.children[0].textContent, "Compilation Error");
      assert.equal(overlay.children[1].textContent, "");
    });

    it("handles multiline content", () => {
      const content = "Line 1\nLine 2\nLine 3";

      LiveReload.showErrorOverlay(content);

      const overlay = document.getElementById(
        "hologram-live-reload-error-overlay",
      );

      assert.isNotNull(overlay);
      assert.isTrue(document.body.contains(overlay));
      assert.equal(overlay.style.whiteSpace, "pre-wrap");

      // Should have proper structure and content
      assert.equal(overlay.children[0].textContent, "Compilation Error");
      assert.equal(overlay.children[1].textContent, content);
    });

    it("disables body scrolling when overlay is shown", () => {
      const content = "Test error message";

      document.body.style.overflow = "visible";

      LiveReload.showErrorOverlay(content);

      assert.equal(document.body.style.overflow, "hidden");
    });
  });
});
