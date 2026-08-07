"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import {
  attributesModule,
  fragment,
  h,
  init,
} from "../../../assets/js/vendor/snabbdom/build/index.js";

defineRuntimeGlobals();

// Covers the deviations Hologram carries in its vendored copy of the diff library, so that an
// upgrade which drops one is caught here rather than in a browser.
describe("vendored snabbdom", () => {
  const patch = init([attributesModule], undefined, {
    experimental: {fragments: true},
  });

  const blockFragment = (key, children) => ({...fragment(children), key});
  const marker = (key) => h("!", {key}, key);

  const render = (children) => {
    const container = document.createElement("div");
    document.body.appendChild(container);

    return patch(container, h("div", {}, children));
  };

  describe("removing a text node from inside a fragment", () => {
    it("removes the text node instead of throwing", () => {
      const before = render([
        blockFragment("a", ["some text", h("p", {}, [])]),
      ]);
      const after = patch(
        before,
        h("div", {}, [blockFragment("a", [h("p", {}, [])])]),
      );

      assert.equal(after.elm.innerHTML, "<p></p>");
    });

    it("empties a fragment holding only text", () => {
      const before = render([blockFragment("a", ["some text"])]);
      const after = patch(before, h("div", {}, [blockFragment("a", [])]));

      assert.equal(after.elm.innerHTML, "");
    });

    // Template indentation puts whitespace text inside every block, so this is the shape an
    // ordinary conditional produces when it is switched off.
    it("switches off a block whose body holds whitespace around an element", () => {
      const on = () =>
        blockFragment("[h:x:0:o]", [
          marker("[h:x:0:o]"),
          "\n    ",
          h("p", {attrs: {class: "hint"}}, ["hint"]),
          "\n  ",
          marker("[h:x:0:c]"),
        ]);

      const off = () =>
        blockFragment("[h:x:0:o]", [marker("[h:x:0:o]"), marker("[h:x:0:c]")]);

      const before = render([on(), h("input", {attrs: {id: "field"}}, [])]);
      const field = before.elm.querySelector("input");
      field.value = "typed";

      const after = patch(
        before,
        h("div", {}, [off(), h("input", {attrs: {id: "field"}}, [])]),
      );

      assert.equal(after.elm.querySelector("input"), field);
      assert.equal(field.value, "typed");
      assert.isNull(after.elm.querySelector(".hint"));
    });
  });
});
