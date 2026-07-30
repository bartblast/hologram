"use strict";

import {
  assert,
  defineRuntimeGlobals,
  JSDOM,
  registerWebApis,
} from "./support/helpers.mjs";

import UncaughtErrorOverlay from "../../assets/js/uncaught_error_overlay.mjs";

defineRuntimeGlobals();
registerWebApis();

const OVERLAY_ID = "hologram-uncaught-error-overlay";

describe("UncaughtErrorOverlay", () => {
  let originalDocument;

  const overlayElement = () => document.getElementById(OVERLAY_ID);

  const pressKey = (key) => {
    document.dispatchEvent(new window.KeyboardEvent("keydown", {key}));
  };

  let window;

  beforeEach(() => {
    originalDocument = globalThis.document;
    ({window} = new JSDOM("<!DOCTYPE html><html><body></body></html>"));
    globalThis.document = window.document;
  });

  afterEach(() => {
    UncaughtErrorOverlay.hide();
    globalThis.document = originalDocument;
  });

  describe("hide()", () => {
    it("removes the overlay", () => {
      UncaughtErrorOverlay.show("my content");
      UncaughtErrorOverlay.hide();

      assert.isNull(overlayElement());
    });

    it("gives the page back its scrolling", () => {
      document.body.style.overflow = "scroll";

      UncaughtErrorOverlay.show("my content");
      UncaughtErrorOverlay.hide();

      assert.equal(document.body.style.overflow, "scroll");
    });

    it("does nothing when no overlay is shown", () => {
      document.body.style.overflow = "scroll";

      UncaughtErrorOverlay.hide();

      assert.isNull(overlayElement());
      assert.equal(document.body.style.overflow, "scroll");
    });

    it("leaves the page alone when Escape is pressed after dismissal", () => {
      UncaughtErrorOverlay.show("my content");
      UncaughtErrorOverlay.hide();

      document.body.style.overflow = "scroll";
      pressKey("Escape");

      assert.equal(document.body.style.overflow, "scroll");
    });
  });

  describe("show()", () => {
    it("renders the given content", () => {
      UncaughtErrorOverlay.show("** (MyError) my message");

      const overlay = overlayElement();

      assert.isTrue(document.body.contains(overlay));
      assert.equal(overlay.lastChild.textContent, "** (MyError) my message");
    });

    it("names the error kind in the heading", () => {
      UncaughtErrorOverlay.show("my content");

      const heading = overlayElement().querySelector("h1");

      assert.equal(heading.textContent, "Runtime Error");
      assert.equal(heading.style.color, "rgb(167, 139, 250)");
    });

    it("keeps a multiline stacktrace laid out as written", () => {
      const content =
        "** (MyError) my message\n    lib/my_module.ex:11: MyModule.my_fun/1\n";

      UncaughtErrorOverlay.show(content);

      const overlay = overlayElement();

      assert.equal(overlay.style.whiteSpace, "pre-wrap");
      assert.equal(overlay.lastChild.textContent, content);
    });

    it("covers the page", () => {
      UncaughtErrorOverlay.show("my content");

      const style = overlayElement().style;

      assert.equal(style.position, "fixed");
      assert.equal(style.width, "100vw");
      assert.equal(style.height, "100vh");
      assert.equal(style.zIndex, "2147483647");
      assert.equal(style.backgroundColor, "rgb(15, 16, 20)");
    });

    it("takes away the page's scrolling", () => {
      document.body.style.overflow = "scroll";

      UncaughtErrorOverlay.show("my content");

      assert.equal(document.body.style.overflow, "hidden");
    });

    it("shows only the newest error", () => {
      UncaughtErrorOverlay.show("first content");
      UncaughtErrorOverlay.show("second content");

      assert.equal(document.querySelectorAll(`#${OVERLAY_ID}`).length, 1);
      assert.equal(overlayElement().lastChild.textContent, "second content");
    });

    it("gives the page back its own scrolling after replacing an overlay", () => {
      document.body.style.overflow = "scroll";

      UncaughtErrorOverlay.show("first content");
      UncaughtErrorOverlay.show("second content");
      UncaughtErrorOverlay.hide();

      assert.equal(document.body.style.overflow, "scroll");
    });

    it("dismisses on the dismiss button", () => {
      UncaughtErrorOverlay.show("my content");

      overlayElement().querySelector("button").click();

      assert.isNull(overlayElement());
    });

    it("dismisses on Escape", () => {
      UncaughtErrorOverlay.show("my content");

      pressKey("Escape");

      assert.isNull(overlayElement());
    });

    it("stays on any other key", () => {
      UncaughtErrorOverlay.show("my content");

      pressKey("Enter");

      assert.isNotNull(overlayElement());
    });
  });
});
