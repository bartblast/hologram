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

  describe("moving a fragment among its siblings", () => {
    const block = (key, text) =>
      blockFragment(`${key}:o`, [
        marker(`${key}:o`),
        h("em", {}, [text]),
        marker(`${key}:c`),
      ]);

    // A fragment empties itself into the page when it is inserted, so the diff moving a block
    // among its siblings hands back a fragment with nothing in it. Without the deviation the move
    // inserts nothing and the block's nodes stay where they were, while its siblings take their
    // new places - the shape a reorder produces once the diff trusts the keys.
    it("carries the nodes the fragment stands for", () => {
      const before = render([
        block("a", "A"),
        h("p", {}, ["one"]),
        block("b", "B"),
        h("p", {}, ["two"]),
      ]);

      const after = patch(
        before,
        h("div", {}, [
          block("b", "B"),
          h("p", {}, ["two"]),
          block("a", "A"),
          h("p", {}, ["one"]),
        ]),
      );

      assert.equal(
        after.elm.innerHTML,
        "<!--b:o--><em>B</em><!--b:c--><p>two</p>" +
          "<!--a:o--><em>A</em><!--a:c--><p>one</p>",
      );
    });

    it("keeps the nodes a fragment holds, so their state survives the move", () => {
      const input = (id) => h("input", {attrs: {id: id}}, []);

      const before = render([
        blockFragment("a:o", [marker("a:o"), input("field_a"), marker("a:c")]),
        h("p", {}, ["one"]),
        blockFragment("b:o", [marker("b:o"), input("field_b"), marker("b:c")]),
        h("p", {}, ["two"]),
      ]);

      const fieldA = before.elm.querySelector("#field_a");
      fieldA.value = "typed a";

      const after = patch(
        before,
        h("div", {}, [
          blockFragment("b:o", [
            marker("b:o"),
            input("field_b"),
            marker("b:c"),
          ]),
          h("p", {}, ["two"]),
          blockFragment("a:o", [
            marker("a:o"),
            input("field_a"),
            marker("a:c"),
          ]),
          h("p", {}, ["one"]),
        ]),
      );

      assert.equal(after.elm.querySelector("#field_a"), fieldA);
      assert.equal(fieldA.value, "typed a");
    });
  });
});
