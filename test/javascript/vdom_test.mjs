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
    it("a loop leaves every sibling it renders with its own key", () => {
      // The shape issue #1019 was reported for: every iteration renders the same two places of
      // the same template, so nothing in the list is unique until it is numbered.
      const iteration = () => [
        vnode("li", {attrs: {}, key: "1a2b3c:0"}, []),
        vnode("p", {attrs: {}, key: "1a2b3c:1"}, []),
      ];

      const result = Vdom.finalizeChildren([
        ...iteration(),
        ...iteration(),
        ...iteration(),
      ]);

      const keys = result.map((child) => child.key);

      assert.deepStrictEqual(keys, [
        "1a2b3c:0",
        "1a2b3c:1",
        "1a2b3c:0:1",
        "1a2b3c:1:1",
        "1a2b3c:0:2",
        "1a2b3c:1:2",
      ]);

      assert.equal(new Set(keys).size, keys.length);
    });
  });

  describe("mirror()", () => {
    // The same patch production builds, so these stand for the boot patch rather than a
    // differently configured one.
    const patch = init([attributesModule, eventListenersModule]);

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

    // The shape the root has on every page: the parser puts the whitespace between </head> and
    // <body> inside <html>, so the rendered text that comes before an element finds a text node
    // only after it. A text node stands for any other, so a text vnode allowed to look ahead would
    // take that one and pass over the element in between - the whole head, in the real document.
    it("does not let a text node take one further along", () => {
      // The element carries the key of its place, the way every rendered element does. A node
      // mirrored as itself carries none, so the two no longer match and the patch rebuilds it.
      const {container, patched} = adopt(
        [" ", vnode("p", {attrs: {}, key: "my_key"}, ["hello"])],
        "<p>hello</p> ",
      );

      const serverP = container.querySelector("p");
      patched();

      assert.equal(container.querySelector("p"), serverP);
    });

    // Inside <svg> a tag name keeps its case, and the parser corrects the markup's spelling to the
    // one the spec gives, so the DOM reads back "linearGradient" however it was written.
    it("adopts an element whose tag name carries case", () => {
      // The element carries the key of its place, the way every rendered element does. A node
      // mirrored as itself carries none, so a failed match rebuilds it rather than keeping it.
      const {container, patched} = adopt(
        [
          vnode("svg", {attrs: {}}, [
            vnode("defs", {attrs: {}}, [
              vnode("linearGradient", {attrs: {id: "grad"}, key: "my_key"}, []),
            ]),
          ]),
        ],
        '<svg><defs><linearGradient id="grad"></linearGradient></defs></svg>',
      );

      const serverGradient = container.querySelector("#grad");
      patched();

      assert.equal(container.querySelector("#grad"), serverGradient);
    });

    // A node the render has no counterpart for is written down as it really is, and inside <svg>
    // that means keeping the case. There is no element called "lineargradient".
    it("names a mirrored-as-itself element the way its namespace spells it", () => {
      const {mirrored} = adopt(
        [],
        '<p>hello</p><svg><defs><linearGradient id="grad"></linearGradient></defs></svg>',
      );

      const [paragraph, svg] = mirrored.children;

      assert.equal(paragraph.sel, "p");
      assert.equal(svg.sel, "svg");
      assert.equal(svg.children[0].sel, "defs");
      assert.equal(svg.children[0].children[0].sel, "linearGradient");
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
