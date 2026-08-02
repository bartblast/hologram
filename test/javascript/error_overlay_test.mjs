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

    it("keeps the page's scrolling away while an overlay under a different id is still up", () => {
      document.body.style.overflow = "scroll";

      show();
      show({id: "my_id_2"});
      ErrorOverlay.hide("my_id");

      assert.equal(document.body.style.overflow, "hidden");
    });

    it("gives the page back its scrolling once the last overlay is hidden", () => {
      document.body.style.overflow = "scroll";

      show();
      show({id: "my_id_2"});
      ErrorOverlay.hide("my_id");
      ErrorOverlay.hide("my_id_2");

      assert.equal(document.body.style.overflow, "scroll");
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

    it("names the overlay, the heading and the content by their classes", () => {
      show();

      const overlay = overlayElement();

      assert.equal(overlay.className, "hologram-error-overlay");
      assert.equal(
        overlay.children[0].className,
        "hologram-error-overlay__heading",
      );
      assert.equal(
        overlay.children[1].className,
        "hologram-error-overlay__content",
      );
    });

    it("puts the tones in the page", () => {
      show();

      const style = document.getElementById("hologram-error-overlay-style");

      assert.isNotNull(style);
      assert.equal(style.tagName, "STYLE");
      assert.include(style.textContent, ".hologram-error-overlay__tone-banner");
      assert.include(style.textContent, ".hologram-error-overlay__tone-body");
      assert.include(style.textContent, ".hologram-error-overlay__tone-chrome");
      assert.include(style.textContent, ".hologram-error-overlay__tone-meta");
    });

    it("puts the tones in the page only once", () => {
      show();
      show({id: "my_id_2"});

      const styles = document.querySelectorAll("#hologram-error-overlay-style");

      assert.equal(styles.length, 1);
    });

    it("lays text content out as written", () => {
      const content = "line 1\nline 2";

      show({content});

      assert.equal(overlayElement().children[1].textContent, content);
    });

    it("renders toned content a line at a time", () => {
      show({
        content: [
          [{text: "** (RuntimeError) my error", tone: "banner"}],
          [{text: "my frame", tone: "body"}],
        ],
      });

      const lines = overlayElement().children[1].children;

      assert.equal(lines.length, 2);
      assert.equal(lines[0].textContent, "** (RuntimeError) my error");
      assert.equal(lines[1].textContent, "my frame");
    });

    it("reads a line in the tone it opens with", () => {
      show({
        content: [
          [
            {text: "  3 │ ", tone: "chrome"},
            {text: "    foo()", tone: "body"},
          ],
        ],
      });

      const line = overlayElement().children[1].children[0];

      assert.equal(
        line.className,
        "hologram-error-overlay__line hologram-error-overlay__line--chrome",
      );
    });

    it("sets each segment of a line in its own tone", () => {
      show({
        content: [
          [
            {text: "(hologram 0.9.3) ", tone: "chrome"},
            {text: "lib/my_app.ex:3: ", tone: "meta"},
            {text: "MyApp.bar/0", tone: "body"},
          ],
        ],
      });

      const segments = overlayElement().children[1].children[0].children;

      assert.deepStrictEqual(
        Array.from(segments).map(({className, textContent}) => [
          className,
          textContent,
        ]),
        [
          ["hologram-error-overlay__tone-chrome", "(hologram 0.9.3) "],
          ["hologram-error-overlay__tone-meta", "lib/my_app.ex:3: "],
          ["hologram-error-overlay__tone-body", "MyApp.bar/0"],
        ],
      );
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
