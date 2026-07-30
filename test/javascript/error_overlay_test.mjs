"use strict";

import {
  assert,
  defineRuntimeGlobals,
  JSDOM,
  registerWebApis,
} from "./support/helpers.mjs";

import ErrorOverlay from "../../assets/js/error_overlay.mjs";

defineRuntimeGlobals();
registerWebApis();

describe("ErrorOverlay", () => {
  let originalDocument;
  let window;

  const overlayElement = (id = "my_id") => document.getElementById(id);

  const pressKey = (key) => {
    document.dispatchEvent(new window.KeyboardEvent("keydown", {key}));
  };

  const show = (opts = {}) =>
    ErrorOverlay.show({
      content: "my content",
      heading: "My Heading",
      id: "my_id",
      ...opts,
    });

  beforeEach(() => {
    originalDocument = globalThis.document;
    ({window} = new JSDOM("<!DOCTYPE html><html><body></body></html>"));
    globalThis.document = window.document;
  });

  afterEach(() => {
    ErrorOverlay.hide("my_id");
    ErrorOverlay.hide("my_id_2");
    globalThis.document = originalDocument;
  });

  describe("hide()", () => {
    it("removes the overlay", () => {
      show({dismissable: true});
      ErrorOverlay.hide("my_id");

      assert.isNull(overlayElement());
    });

    it("gives the page back its scrolling", () => {
      document.body.style.overflow = "scroll";

      show({dismissable: true});
      ErrorOverlay.hide("my_id");

      assert.equal(document.body.style.overflow, "scroll");
    });

    it("gives the page back its own scrolling after an overlay was replaced", () => {
      document.body.style.overflow = "scroll";

      show({dismissable: true});
      show({content: "my content 2", dismissable: true});
      ErrorOverlay.hide("my_id");

      assert.equal(document.body.style.overflow, "scroll");
    });

    it("leaves an overlay under a different id alone", () => {
      show();
      show({id: "my_id_2"});

      ErrorOverlay.hide("my_id");

      assert.isNull(overlayElement());
      assert.isNotNull(overlayElement("my_id_2"));
    });

    it("does nothing when no overlay is shown", () => {
      document.body.style.overflow = "scroll";

      ErrorOverlay.hide("my_id");

      assert.isNull(overlayElement());
      assert.equal(document.body.style.overflow, "scroll");
    });

    it("leaves the page alone when Escape is pressed after dismissal", () => {
      show({dismissable: true});
      ErrorOverlay.hide("my_id");

      document.body.style.overflow = "scroll";
      pressKey("Escape");

      assert.equal(document.body.style.overflow, "scroll");
    });
  });

  describe("show()", () => {
    it("puts the overlay in the page under the given id", () => {
      show();

      assert.isTrue(document.body.contains(overlayElement()));
    });

    it("renders the heading and the content, in that order", () => {
      show();

      const overlay = overlayElement();

      assert.equal(overlay.children.length, 2);
      assert.equal(overlay.children[0].tagName, "H1");
      assert.equal(overlay.children[0].textContent, "My Heading");
      assert.equal(overlay.children[1].tagName, "DIV");
      assert.equal(overlay.children[1].textContent, "my content");
    });

    it("covers the page", () => {
      show();

      const style = overlayElement().style;

      assert.equal(style.position, "fixed");
      assert.equal(style.width, "100vw");
      assert.equal(style.height, "100vh");
      assert.equal(style.zIndex, "2147483647");
      assert.equal(style.backgroundColor, "rgb(15, 16, 20)");
      assert.equal(style.color, "rgb(194, 187, 211)");
    });

    it("styles the heading", () => {
      show();

      const style = overlayElement().children[0].style;

      assert.equal(style.marginTop, "0px");
      assert.equal(style.marginBottom, "50px");
      assert.equal(style.fontSize, "36px");
      assert.equal(style.fontWeight, "700");
      assert.equal(style.color, "rgb(167, 139, 250)");
    });

    it("lays the content out as written", () => {
      const content = "line 1\nline 2";

      show({content});

      const overlay = overlayElement();

      assert.equal(overlay.style.whiteSpace, "pre-wrap");
      assert.equal(overlay.children[1].textContent, content);
    });

    it("takes away the page's scrolling", () => {
      document.body.style.overflow = "scroll";

      show();

      assert.equal(document.body.style.overflow, "hidden");
    });

    it("replaces an overlay already up under the same id", () => {
      show();
      show({content: "my content 2"});

      assert.equal(document.querySelectorAll("#my_id").length, 1);
      assert.equal(overlayElement().lastChild.textContent, "my content 2");
      assert.equal(document.body.style.overflow, "hidden");
    });

    it("leaves an overlay up under a different id", () => {
      show();
      show({id: "my_id_2"});

      assert.isNotNull(overlayElement());
      assert.isNotNull(overlayElement("my_id_2"));
    });

    it("keeps the content last when dismissable", () => {
      show({dismissable: true});

      const overlay = overlayElement();

      assert.equal(overlay.children.length, 3);
      assert.equal(overlay.children[0].tagName, "BUTTON");
      assert.equal(overlay.lastChild.textContent, "my content");
    });

    it("dismisses on the dismiss button when dismissable", () => {
      show({dismissable: true});

      overlayElement().querySelector("button").click();

      assert.isNull(overlayElement());
    });

    it("dismisses on Escape when dismissable", () => {
      show({dismissable: true});

      pressKey("Escape");

      assert.isNull(overlayElement());
    });

    it("stays on any other key when dismissable", () => {
      show({dismissable: true});

      pressKey("Enter");

      assert.isNotNull(overlayElement());
    });

    it("offers no dismiss button when not dismissable", () => {
      show();

      assert.isNull(overlayElement().querySelector("button"));
    });

    it("ignores Escape when not dismissable", () => {
      show();

      pressKey("Escape");

      assert.isNotNull(overlayElement());
    });
  });
});
