"use strict";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  vnode,
} from "./support/helpers.mjs";

import Vdom from "../../assets/js/vdom.mjs";

import {
  attributesModule,
  eventListenersModule,
  init,
} from "../../assets/js/vendor/snabbdom/build/index.js";

defineRuntimeGlobals();
registerWebApis();

describe("Vdom", () => {
  describe("dedupeKeys()", () => {
    it("distinct marker keys", () => {
      const children = [
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("!", {key: "[h:1a2b3c:0:c]"}, "[h:1a2b3c:0:c]"),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        ["[h:1a2b3c:0:o]", "[h:1a2b3c:0:c]"],
      );
    });

    it("repeated marker keys", () => {
      const children = [
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        ["[h:1a2b3c:0:o]", "[h:1a2b3c:0:o]:1", "[h:1a2b3c:0:o]:2"],
      );
    });

    it("renumbers the vnode key without touching the comment text", () => {
      const children = [
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.text),
        ["[h:1a2b3c:0:o]", "[h:1a2b3c:0:o]"],
      );

      assert.equal(children[1].data.key, "[h:1a2b3c:0:o]:1");
    });

    it("ordinary comments and elements", () => {
      const children = [
        vnode("!", "my comment"),
        vnode("!", "my comment"),
        vnode("div", {attrs: {}}, []),
        vnode("div", {attrs: {}}, []),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        [undefined, undefined, undefined, undefined],
      );
    });

    it("repeated element keys", () => {
      // What a loop renders: one place in the template, once per iteration.
      const children = [
        vnode("li", {attrs: {}, key: "1a2b3c:0"}, []),
        vnode("li", {attrs: {}, key: "1a2b3c:0"}, []),
        vnode("li", {attrs: {}, key: "1a2b3c:0"}, []),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        ["1a2b3c:0", "1a2b3c:0:1", "1a2b3c:0:2"],
      );
    });

    it("renumbers the vnode key and the data it was read from", () => {
      const children = [
        vnode("li", {attrs: {}, key: "1a2b3c:0"}, []),
        vnode("li", {attrs: {}, key: "1a2b3c:0"}, []),
      ];

      Vdom.dedupeKeys(children);

      assert.equal(children[1].data.key, "1a2b3c:0:1");
    });

    it("each key is counted on its own", () => {
      const children = [
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("li", {attrs: {}, key: "1a2b3c:1"}, []),
        vnode("li", {attrs: {}, key: "1a2b3c:2"}, []),
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("li", {attrs: {}, key: "1a2b3c:1"}, []),
        vnode("li", {attrs: {}, key: "1a2b3c:2"}, []),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        [
          "[h:1a2b3c:0:o]",
          "1a2b3c:1",
          "1a2b3c:2",
          "[h:1a2b3c:0:o]:1",
          "1a2b3c:1:1",
          "1a2b3c:2:1",
        ],
      );
    });

    it("repeated resource keys", () => {
      // The same stylesheet named twice in one list still has to name two nodes.
      const children = [
        vnode("link", {attrs: {}, key: "__hologramLink__:/my.css"}, []),
        vnode("link", {attrs: {}, key: "__hologramLink__:/my.css"}, []),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        ["__hologramLink__:/my.css", "__hologramLink__:/my.css:1"],
      );
    });

    it("a single child is left alone", () => {
      const children = [vnode("li", {attrs: {}, key: "1a2b3c:0"}, [])];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        ["1a2b3c:0"],
      );
    });
  });

  describe("finalizeChildren()", () => {
    it("numbers repeated marker keys, then gathers each marked span into a fragment", () => {
      const marker = (side, index) =>
        vnode(
          "!",
          {key: `[h:1a2b3c:${index}:${side}]`},
          `[h:1a2b3c:${index}:${side}]`,
        );

      const children = [
        marker("o", 0),
        vnode("div", {attrs: {}}, []),
        marker("c", 0),
        marker("o", 0),
        vnode("span", {attrs: {}}, []),
        marker("c", 0),
      ];

      const result = Vdom.finalizeChildren(children);

      assert.deepStrictEqual(
        result.map((child) => child.key),
        ["[h:1a2b3c:0:o]", "[h:1a2b3c:0:o]:1"],
      );

      assert.deepStrictEqual(
        result.map((fragment) =>
          fragment.children.map((child) => child.key ?? child.sel),
        ),
        [
          ["[h:1a2b3c:0:o]", "div", "[h:1a2b3c:0:c]"],
          ["[h:1a2b3c:0:o]:1", "span", "[h:1a2b3c:0:c]:1"],
        ],
      );
    });

    it("a loop whose body holds a block leaves every sibling with its own key", () => {
      // The shape issue #1019 was reported for: each iteration renders the same element and the
      // same block, so nothing in the list is unique until it is numbered.
      const marker = (side) =>
        vnode("!", {key: `[h:1a2b3c:0:${side}]`}, `[h:1a2b3c:0:${side}]`);

      const iteration = () => [
        vnode("li", {attrs: {}, key: "1a2b3c:0"}, []),
        marker("o"),
        vnode("p", {attrs: {}, key: "1a2b3c:1"}, []),
        marker("c"),
      ];

      const result = Vdom.finalizeChildren([
        ...iteration(),
        ...iteration(),
        ...iteration(),
      ]);

      const keys = result.map((child) => child.key);

      assert.deepStrictEqual(keys, [
        "1a2b3c:0",
        "[h:1a2b3c:0:o]",
        "1a2b3c:0:1",
        "[h:1a2b3c:0:o]:1",
        "1a2b3c:0:2",
        "[h:1a2b3c:0:o]:2",
      ]);

      assert.equal(new Set(keys).size, keys.length);
    });
  });

  describe("groupBlockFragments()", () => {
    const marker = (key) => vnode("!", {key}, key);

    const keysOf = (children) =>
      children.map((child) =>
        typeof child === "string" ? child : (child.key ?? child.sel ?? "text"),
      );

    it("children list without markers is returned unchanged", () => {
      const children = [vnode("div", {attrs: {}}, []), "abc"];
      const result = Vdom.groupBlockFragments(children);

      assert.equal(result, children);
    });

    it("marked span becomes a single keyed fragment", () => {
      const children = [
        "before",
        marker("[h:1a2b3c:0:o]"),
        vnode("p", {attrs: {}}, []),
        marker("[h:1a2b3c:0:c]"),
        vnode("input", {attrs: {}}, []),
      ];

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), [
        "before",
        "[h:1a2b3c:0:o]",
        "input",
      ]);

      const fragment = result[1];

      assert.isUndefined(fragment.sel);
      assert.deepStrictEqual(keysOf(fragment.children), [
        "[h:1a2b3c:0:o]",
        "p",
        "[h:1a2b3c:0:c]",
      ]);
    });

    it("empty span becomes a fragment holding only its markers", () => {
      const children = [
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:c]"),
        vnode("input", {attrs: {}}, []),
      ];

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), ["[h:1a2b3c:0:o]", "input"]);
      assert.equal(result[0].children.length, 2);
    });

    it("sibling spans become separate fragments", () => {
      const children = [
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:c]"),
        vnode("input", {attrs: {}}, []),
        marker("[h:1a2b3c:1:o]"),
        marker("[h:1a2b3c:1:c]"),
      ];

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), [
        "[h:1a2b3c:0:o]",
        "input",
        "[h:1a2b3c:1:o]",
      ]);
    });

    it("nested spans become nested fragments", () => {
      const children = [
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:1:o]"),
        vnode("b", {attrs: {}}, []),
        marker("[h:1a2b3c:1:c]"),
        marker("[h:1a2b3c:0:c]"),
      ];

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), ["[h:1a2b3c:0:o]"]);

      const outer = result[0];

      assert.deepStrictEqual(keysOf(outer.children), [
        "[h:1a2b3c:0:o]",
        "[h:1a2b3c:1:o]",
        "[h:1a2b3c:0:c]",
      ]);

      assert.deepStrictEqual(keysOf(outer.children[1].children), [
        "[h:1a2b3c:1:o]",
        "b",
        "[h:1a2b3c:1:c]",
      ]);
    });

    it("renumbered repeats pair with their own closing side", () => {
      const children = [
        marker("[h:1a2b3c:0:o]"),
        vnode("b", {attrs: {}}, []),
        marker("[h:1a2b3c:0:c]"),
        marker("[h:1a2b3c:0:o]:1"),
        vnode("i", {attrs: {}}, []),
        marker("[h:1a2b3c:0:c]:1"),
      ];

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), [
        "[h:1a2b3c:0:o]",
        "[h:1a2b3c:0:o]:1",
      ]);

      assert.deepStrictEqual(keysOf(result[1].children), [
        "[h:1a2b3c:0:o]:1",
        "i",
        "[h:1a2b3c:0:c]:1",
      ]);
    });

    it("same block nested inside itself pairs by depth", () => {
      // A component whose template holds a block that renders the component again, with nothing
      // between them, splices both renderings into one children list under the same marker.
      const children = [
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:o]"),
        vnode("p", {attrs: {}}, []),
        marker("[h:1a2b3c:0:c]"),
        marker("[h:1a2b3c:0:c]"),
      ];

      Vdom.dedupeKeys(children);

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), ["[h:1a2b3c:0:o]"]);

      const outer = result[0];

      assert.deepStrictEqual(keysOf(outer.children), [
        "[h:1a2b3c:0:o]",
        "[h:1a2b3c:0:o]:1",
        "[h:1a2b3c:0:c]:1",
      ]);

      assert.deepStrictEqual(keysOf(outer.children[1].children), [
        "[h:1a2b3c:0:o]:1",
        "p",
        "[h:1a2b3c:0:c]",
      ]);
    });

    it("same block nested inside itself twice over", () => {
      const children = [
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:o]"),
        vnode("p", {attrs: {}}, []),
        marker("[h:1a2b3c:0:c]"),
        marker("[h:1a2b3c:0:c]"),
        marker("[h:1a2b3c:0:c]"),
      ];

      Vdom.dedupeKeys(children);

      const result = Vdom.groupBlockFragments(children);
      const depth = (children) =>
        children.length === 0
          ? 0
          : 1 +
            Math.max(
              ...children.map((child) =>
                child.children ? depth(child.children) : 0,
              ),
            );

      assert.equal(result.length, 1);
      assert.equal(depth(result), 4);
    });

    it("same block nested inside itself, followed by a sibling rendering", () => {
      const children = [
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:c]"),
        marker("[h:1a2b3c:0:c]"),
        marker("[h:1a2b3c:0:o]"),
        marker("[h:1a2b3c:0:c]"),
      ];

      Vdom.dedupeKeys(children);

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), [
        "[h:1a2b3c:0:o]",
        "[h:1a2b3c:0:o]:2",
      ]);
    });

    it("opening marker without a matching close leaves the list flat", () => {
      const children = [marker("[h:1a2b3c:0:o]"), vnode("p", {attrs: {}}, [])];

      const result = Vdom.groupBlockFragments(children);

      assert.deepStrictEqual(keysOf(result), ["[h:1a2b3c:0:o]", "p"]);
    });

    it("fragment grouped from live nodes stands for the span they occupy", () => {
      const container = document.createElement("div");
      container.innerHTML = "<!--[h:1a2b3c:0:o]--><p></p><!--[h:1a2b3c:0:c]-->";

      const [openNode, contentNode, closeNode] = [...container.childNodes];

      const children = [
        {...marker("[h:1a2b3c:0:o]"), elm: openNode},
        {...vnode("p", {attrs: {}}, []), elm: contentNode},
        {...marker("[h:1a2b3c:0:c]"), elm: closeNode},
      ];

      const [blockFragment] = Vdom.groupBlockFragments(children);

      assert.equal(blockFragment.elm.nodeType, 11);
      assert.equal(blockFragment.elm.parent, container);
      assert.equal(blockFragment.elm.firstChildNode, openNode);
      assert.equal(blockFragment.elm.lastChildNode, closeNode);
    });

    it("fragment grouped from parsed markup has no live node", () => {
      const children = [marker("[h:1a2b3c:0:o]"), marker("[h:1a2b3c:0:c]")];
      const [blockFragment] = Vdom.groupBlockFragments(children);

      assert.isUndefined(blockFragment.elm);
    });

    it("ordinary comments are left alone", () => {
      const children = [
        vnode("!", "my comment"),
        vnode("div", {attrs: {}}, []),
      ];
      const result = Vdom.groupBlockFragments(children);

      assert.equal(result, children);
    });
  });

  describe("markerKey()", () => {
    it("opening marker", () => {
      assert.equal(Vdom.markerKey("[h:1a2b3c:0:o]"), "[h:1a2b3c:0:o]");
    });

    it("closing marker", () => {
      assert.equal(Vdom.markerKey("[h:1a2b3c:12:c]"), "[h:1a2b3c:12:c]");
    });

    it("ordinary comment text", () => {
      assert.isNull(Vdom.markerKey(" my comment "));
    });

    it("marker with surrounding text", () => {
      assert.isNull(Vdom.markerKey("abc [h:1a2b3c:0:o] xyz"));
    });

    it("marker with invalid side", () => {
      assert.isNull(Vdom.markerKey("[h:1a2b3c:0:x]"));
    });

    it("marker with non-numeric block index", () => {
      assert.isNull(Vdom.markerKey("[h:1a2b3c:abc:o]"));
    });

    it("non-string text", () => {
      assert.isNull(Vdom.markerKey(undefined));
    });
  });

  describe("mirror()", () => {
    const patch = init([attributesModule, eventListenersModule], undefined, {
      experimental: {fragments: true},
    });

    const mount = (html) => {
      const container = document.createElement("div");
      container.innerHTML = html;
      document.body.appendChild(container);

      return container;
    };

    // Mirror against the container, then run the boot patch the way render() will: the mirrored
    // tree as the old side, the rendered tree as the new one.
    const adopt = (renderedChildren, html) => {
      const container = mount(html);
      const rendered = vnode("div", {attrs: {}}, renderedChildren);
      const mirrored = Vdom.mirror(rendered, container);

      return {container, mirrored, patched: () => patch(mirrored, rendered)};
    };

    it("adopts a matching tree, copying sel and key from the rendered side", () => {
      const container = mount('<div id="app"><p>hello</p></div>');

      const rendered = vnode("div", {attrs: {id: "app"}, key: "my_key"}, [
        vnode("p", {attrs: {}}, ["hello"]),
      ]);

      const mirrored = Vdom.mirror(rendered, container.firstChild);

      assert.equal(mirrored.sel, "div");
      assert.equal(mirrored.key, "my_key");
      assert.deepStrictEqual(mirrored.data.attrs, {id: "app"});
      assert.equal(mirrored.elm, container.firstChild);

      const [p] = mirrored.children;
      assert.equal(p.sel, "p");
      assert.equal(p.elm, container.firstChild.firstChild);
      assert.equal(p.children[0].text, "hello");
      assert.equal(p.children[0].elm, p.elm.firstChild);
    });

    it("keeps the server's nodes through the boot patch and attaches listeners", () => {
      let clicks = 0;

      const {container, patched} = adopt(
        [vnode("button", {attrs: {}, on: {click: () => clicks++}}, ["go"])],
        "<button>go</button>",
      );

      const serverButton = container.querySelector("button");
      patched();

      assert.equal(container.querySelector("button"), serverButton);

      serverButton.dispatchEvent(new window.Event("click"));
      assert.equal(clicks, 1);
    });

    it("syncs attributes to the rendered side without replacing the node", () => {
      const {container, patched} = adopt(
        [vnode("p", {attrs: {class: "fresh"}}, [])],
        '<p class="stale" data-junk="1"></p>',
      );

      const serverP = container.querySelector("p");
      patched();

      assert.equal(container.querySelector("p"), serverP);
      assert.equal(serverP.getAttribute("class"), "fresh");
      assert.isFalse(serverP.hasAttribute("data-junk"));
    });

    it("adopts a text node whose content differs and patches it in place", () => {
      const {container, patched} = adopt(
        [vnode("p", {attrs: {}}, ["fresh"])],
        "<p>stale</p>",
      );

      const serverText = container.querySelector("p").firstChild;
      patched();

      assert.equal(container.querySelector("p").firstChild, serverText);
      assert.equal(serverText.textContent, "fresh");
    });

    it("replaces a subtree whose tag diverges", () => {
      const {container, patched} = adopt(
        [vnode("div", {attrs: {}}, [])],
        "<span>old</span>",
      );

      const serverSpan = container.querySelector("span");
      patched();

      assert.isNull(container.querySelector("span"));
      assert.notEqual(container.querySelector("div"), serverSpan);
      assert.equal(container.firstChild.tagName, "DIV");
    });

    it("removes DOM nodes the rendered side doesn't know about", () => {
      const {container, patched} = adopt(
        [vnode("p", {attrs: {}}, [])],
        "<p></p><i>injected</i>",
      );

      patched();

      assert.isNull(container.querySelector("i"));
      assert.equal(container.childNodes.length, 1);
    });

    it("creates rendered nodes with no DOM counterpart", () => {
      const {container, patched} = adopt(
        [vnode("p", {attrs: {}}, []), vnode("em", {attrs: {}}, [])],
        "<p></p>",
      );

      const serverP = container.querySelector("p");
      patched();

      assert.equal(container.querySelector("p"), serverP);
      assert.equal(container.querySelector("em").tagName, "EM");
    });

    it("mirrors a marked span as a fragment bracketing the server's nodes", () => {
      const renderedChildren = Vdom.finalizeChildren([
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("em", {attrs: {}}, ["*"]),
        vnode("!", {key: "[h:1a2b3c:0:c]"}, "[h:1a2b3c:0:c]"),
        vnode("input", {attrs: {}}, []),
      ]);

      const {container, mirrored, patched} = adopt(
        renderedChildren,
        "<!--[h:1a2b3c:0:o]--><em>*</em><!--[h:1a2b3c:0:c]--><input>",
      );

      const [mirroredFragment, mirroredInput] = mirrored.children;

      assert.isUndefined(mirroredFragment.sel);
      assert.equal(mirroredFragment.key, "[h:1a2b3c:0:o]");
      assert.equal(mirroredFragment.children.length, 3);
      assert.equal(
        mirroredFragment.elm.firstChildNode,
        container.childNodes[0],
      );
      assert.equal(mirroredFragment.elm.lastChildNode, container.childNodes[2]);
      assert.equal(mirroredFragment.elm.parent, container);
      assert.equal(mirroredInput.elm, container.querySelector("input"));

      const serverEm = container.querySelector("em");
      patched();

      assert.equal(container.querySelector("em"), serverEm);
    });

    // The boot render omits the runtime's own scripts: they are guarded by page_mounted?, which
    // the server sets to true in the struct it serializes to the client. So the render is not a
    // node-for-node prefix of the head, and the stylesheet after those scripts still has to be
    // adopted rather than re-fetched.
    it("passes over nodes the render omits and adopts what follows", () => {
      const {container, patched} = adopt(
        [
          vnode("meta", {attrs: {charset: "utf-8"}}, []),
          vnode(
            "link",
            {
              key: "__hologramLink__:/app.css",
              attrs: {rel: "stylesheet", href: "/app.css"},
            },
            [],
          ),
          vnode("style", {attrs: {}}, ["body { color: red; }"]),
        ],
        '<meta charset="utf-8">' +
          "<script>globalThis.Hologram = {}</script>" +
          '<script src="/hologram/runtime.js"></script>' +
          '<link rel="stylesheet" href="/app.css">' +
          "<style>body { color: red; }</style>",
      );

      const serverMeta = container.querySelector("meta");
      const serverLink = container.querySelector("link");
      const serverStyle = container.querySelector("style");

      patched();

      assert.equal(container.querySelector("meta"), serverMeta);
      assert.equal(container.querySelector("link"), serverLink);
      assert.equal(container.querySelector("style"), serverStyle);
      assert.equal(container.querySelectorAll("script").length, 0);

      // A node mirrored as itself has to report its children truthfully, or the patch appends
      // content it already holds.
      assert.equal(serverStyle.textContent, "body { color: red; }");
    });

    it("does not adopt a script element for a different source", () => {
      const {container, patched} = adopt(
        [
          vnode(
            "script",
            {
              key: "__hologramScript__:/fresh.js",
              attrs: {src: "/fresh.js"},
            },
            [],
          ),
        ],
        '<script src="/stale.js"></script>',
      );

      const serverScript = container.querySelector("script");
      patched();

      // Adopting would have left the stale code running, since changing src on a script that has
      // already executed does not run the new one.
      assert.notEqual(container.querySelector("script"), serverScript);
      assert.equal(
        container.querySelector("script").getAttribute("src"),
        "/fresh.js",
      );
    });

    it("keeps a script whose rendered key matches, so it is not re-executed", () => {
      const rendered = vnode(
        "script",
        {key: "__hologramScript__:my_src", attrs: {src: "my_src"}},
        [],
      );

      const {container, patched} = adopt(
        [rendered],
        '<script src="my_src"></script>',
      );

      const serverScript = container.querySelector("script");
      patched();

      assert.equal(container.querySelector("script"), serverScript);
    });
  });
});
