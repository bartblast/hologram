"use strict";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
  vnode,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import TrustedTypes from "../../assets/js/trusted_types.mjs";
import Vdom from "../../assets/js/vdom.mjs";

import {init} from "../../assets/js/vendor/snabbdom/build/index.js";

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

    it("skips a number a later sibling's key holds", () => {
      const children = [
        vnode("li", {attrs: {}, key: "K"}, []),
        vnode("li", {attrs: {}, key: "K"}, []),
        vnode("li", {attrs: {}, key: "K:1"}, []),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        ["K", "K:2", "K:1"],
      );
    });

    it("skips a number an earlier sibling's key holds", () => {
      const children = [
        vnode("li", {attrs: {}, key: "K"}, []),
        vnode("li", {attrs: {}, key: "K:1"}, []),
        vnode("li", {attrs: {}, key: "K"}, []),
        vnode("li", {attrs: {}, key: "K"}, []),
      ];

      Vdom.dedupeKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        ["K", "K:1", "K:2", "K:3"],
      );
    });

    describe("duplicate key warning", () => {
      let warnStub;

      beforeEach(() => {
        warnStub = sinon.stub(console, "warn");
      });

      afterEach(() => {
        warnStub.restore();
      });

      const scoped = (key, scope) =>
        vnode("li", {attrs: {}, key, hologramKeyScope: scope}, []);

      it("a key repeated across two item scopes is logged", () => {
        Vdom.dedupeKeys([
          scoped("vdom_warn_1#i1", {level: "#i1", outer: ""}),
          scoped("vdom_warn_1#i1", {level: "#i1", outer: ""}),
        ]);

        sinon.assert.calledOnceWithExactly(
          warnStub,
          'Hologram: sibling elements share the key "vdom_warn_1#i1", so they\'re matched by position. Give each loop item a unique :id or $key.',
        );
      });

      it("is logged once per key", () => {
        const render = () =>
          Vdom.dedupeKeys([
            scoped("vdom_warn_2#i1", {level: "#i1", outer: ""}),
            scoped("vdom_warn_2#i1", {level: "#i1", outer: ""}),
            scoped("vdom_warn_2#i1", {level: "#i1", outer: ""}),
          ]);

        render();
        render();

        sinon.assert.calledOnce(warnStub);
      });

      it("a key repeated within one item scope isn't logged", () => {
        const scope = {level: "#i1", outer: ""};

        Vdom.dedupeKeys([
          scoped("vdom_warn_3#i1", scope),
          scoped("vdom_warn_3#i1", scope),
        ]);

        sinon.assert.notCalled(warnStub);
      });

      it("a key repeated across the scopes of two loops isn't logged", () => {
        Vdom.dedupeKeys([
          scoped("vdom_warn_5#i1", {level: "#i1", outer: "", loop: {}}),
          scoped("vdom_warn_5#i1", {level: "#i1", outer: "", loop: {}}),
        ]);

        sinon.assert.notCalled(warnStub);
      });

      it("a key repeated without scopes isn't logged", () => {
        Vdom.dedupeKeys([
          vnode("li", {attrs: {}, key: "vdom_warn_4"}, []),
          vnode("li", {attrs: {}, key: "vdom_warn_4"}, []),
        ]);

        sinon.assert.notCalled(warnStub);
      });
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
    const patch = init(Vdom.patchModules, Vdom.domApi);

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
              attrs: {},
              hologramScript: {code: null, src: "/fresh.js"},
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
        {
          key: "__hologramScript__:my_src",
          attrs: {},
          hologramScript: {code: null, src: "my_src"},
        },
        [],
      );

      const {container, patched} = adopt(
        [rendered],
        '<script src="my_src"></script>',
      );

      const serverScript = container.querySelector("script");
      patched();

      assert.equal(container.querySelector("script"), serverScript);
      assert.equal(serverScript.getAttribute("src"), "my_src");
    });

    // The script carries its code in data.hologramScript on both sides, so the patch leaves the
    // text the server sent where it is.
    it("keeps the code of an inline script the server sent", () => {
      const rendered = vnode(
        "script",
        {
          key: "__hologramScript__:go();",
          attrs: {type: "text/javascript"},
          hologramScript: {code: "go();", src: null},
        },
        [],
      );

      const {container, mirrored, patched} = adopt(
        [rendered],
        '<script type="text/javascript">go();</script>',
      );

      const serverScript = container.querySelector("script");

      assert.deepStrictEqual(mirrored.children[0].data.hologramScript, {
        code: "go();",
        src: null,
      });

      patched();

      assert.equal(container.querySelector("script"), serverScript);
      assert.equal(serverScript.textContent, "go();");
      assert.equal(serverScript.getAttribute("type"), "text/javascript");
    });

    it("leaves the nonce of a server-rendered element in place", () => {
      const {container, mirrored, patched} = adopt(
        [vnode("style", {attrs: {}}, ["a {}"])],
        '<style nonce="my_nonce">a {}</style>',
      );

      assert.deepStrictEqual(mirrored.children[0].data.attrs, {});

      patched();

      assert.equal(container.querySelector("style").nonce, "my_nonce");
    });

    describe("trusted HTML range", () => {
      let warnStub;

      beforeEach(() => {
        warnStub = sinon.stub(console, "warn");
      });

      afterEach(() => {
        warnStub.restore();
      });

      it("adopts the server's nodes and keeps them through the boot patch", () => {
        const {container, patched} = adopt(
          [
            vnode("p", {attrs: {}}, ["a"]),
            Vdom.trustedHtmlVnode("<b>b</b>", null),
            vnode("p", {attrs: {}}, ["c"]),
          ],
          "<p>a</p><!--hologram-html--><b>b</b><!--/hologram-html--><p>c</p>",
        );

        const bold = container.querySelector("b");
        const lastParagraph = container.lastChild;

        patched();

        assert.equal(
          container.innerHTML,
          "<p>a</p><!--hologram-html--><b>b</b><!--/hologram-html--><p>c</p>",
        );

        assert.strictEqual(container.querySelector("b"), bold);
        assert.strictEqual(container.lastChild, lastParagraph);
        sinon.assert.notCalled(warnStub);
      });

      it("rewrites an adopted range when its HTML changes later", () => {
        const {container, patched} = adopt(
          [Vdom.trustedHtmlVnode("<b>b</b>", null)],
          "<!--hologram-html--><b>b</b><!--/hologram-html-->",
        );

        const booted = patched();

        patch(
          booted,
          vnode("div", {attrs: {}}, [Vdom.trustedHtmlVnode("<i>c</i>", null)]),
        );

        sinon.assert.notCalled(warnStub);

        assert.equal(
          container.innerHTML,
          "<!--hologram-html--><i>c</i><!--/hologram-html-->",
        );
      });

      it("adopts the range after nodes the render omits", () => {
        const {container, patched} = adopt(
          [Vdom.trustedHtmlVnode("<b>b</b>", null)],
          "<span>x</span><!--hologram-html--><b>b</b><!--/hologram-html-->",
        );

        const bold = container.querySelector("b");

        patched();

        assert.equal(
          container.innerHTML,
          "<!--hologram-html--><b>b</b><!--/hologram-html-->",
        );

        assert.strictEqual(container.querySelector("b"), bold);
      });

      it("adopts two ranges side by side", () => {
        const {container, patched} = adopt(
          [
            Vdom.trustedHtmlVnode("<b>a</b>", null),
            Vdom.trustedHtmlVnode("<i>b</i>", null),
          ],
          "<!--hologram-html--><b>a</b><!--/hologram-html--><!--hologram-html--><i>b</i><!--/hologram-html-->",
        );

        const bold = container.querySelector("b");
        const italic = container.querySelector("i");

        patched();

        assert.strictEqual(container.querySelector("b"), bold);
        assert.strictEqual(container.querySelector("i"), italic);
        sinon.assert.notCalled(warnStub);

        assert.equal(
          container.innerHTML,
          "<!--hologram-html--><b>a</b><!--/hologram-html--><!--hologram-html--><i>b</i><!--/hologram-html-->",
        );
      });

      it("creates a range the page doesn't hold", () => {
        const {container, patched} = adopt(
          [
            vnode("p", {attrs: {}}, ["a"]),
            Vdom.trustedHtmlVnode("<b>b</b>", null),
          ],
          "<p>a</p>",
        );

        patched();

        assert.equal(
          container.innerHTML,
          "<p>a</p><!--hologram-html--><b>b</b><!--/hologram-html-->",
        );
      });

      it("keeps content that differs from what the HTML parses to, and warns", () => {
        const {container, patched} = adopt(
          [Vdom.trustedHtmlVnode("<b>b</b>", "MyModule")],
          "<!--hologram-html--><font>b</font><!--/hologram-html-->",
        );

        patched();

        assert.equal(
          container.innerHTML,
          "<!--hologram-html--><font>b</font><!--/hologram-html-->",
        );

        sinon.assert.calledOnceWithExactly(
          warnStub,
          "Hologram: the page's nodes for trusted HTML rendered in MyModule differ from what its HTML parses to, so they're kept as they are until the HTML changes. The browser's HTML parser may have changed them because the HTML isn't valid where it's placed, or something like a browser extension changed the page - see https://hologram.page/docs/template-syntax",
        );
      });

      it("warns when the page holds fewer nodes than the HTML parses to", () => {
        const {patched} = adopt(
          [Vdom.trustedHtmlVnode("<b>a</b><b>b</b>", null)],
          "<!--hologram-html--><b>a</b><!--/hologram-html-->",
        );

        patched();

        sinon.assert.calledOnce(warnStub);
      });

      it("raises when the browser's parser split the range", () => {
        // A <div> closes the <p>, so the range's end lands after it, outside the <p>.
        const container = mount(
          "<p><!--hologram-html--><div>b</div><!--/hologram-html--></p>",
        );

        const rendered = vnode("div", {attrs: {}}, [
          vnode("p", {attrs: {}}, [
            Vdom.trustedHtmlVnode("<div>b</div>", "MyModule"),
          ]),
        ]);

        assert.throws(
          () => Vdom.mirror(rendered, container),
          HologramRuntimeError,
          "trusted HTML rendered in MyModule was moved by the browser's HTML parser, because it isn't valid HTML where it's placed, like a <div> inside a <p> - see https://hologram.page/docs/template-syntax",
        );
      });

      it("raises when the browser's parser moved all of the content out of the range", () => {
        // A table can't hold a <div>, so the parser moves it before the table.
        const container = mount(
          "<table><!--hologram-html--><div>x</div><!--/hologram-html--></table>",
        );

        const rendered = vnode("div", {attrs: {}}, [
          vnode("table", {attrs: {}}, [
            Vdom.trustedHtmlVnode("<div>x</div>", "MyModule"),
          ]),
        ]);

        assert.throws(
          () => Vdom.mirror(rendered, container),
          HologramRuntimeError,
          "trusted HTML rendered in MyModule was moved by the browser's HTML parser, because it isn't valid HTML where it's placed, like a <div> inside a <p> - see https://hologram.page/docs/template-syntax",
        );
      });

      it("adopts an empty range for empty HTML", () => {
        const {container, patched} = adopt(
          [Vdom.trustedHtmlVnode("", null)],
          "<!--hologram-html--><!--/hologram-html-->",
        );

        patched();

        assert.equal(
          container.innerHTML,
          "<!--hologram-html--><!--/hologram-html-->",
        );
        sinon.assert.notCalled(warnStub);
      });

      it("raises when the next range starts before the range ends", () => {
        const container = mount(
          "<!--hologram-html--><b>a</b><!--hologram-html--><i>b</i><!--/hologram-html-->",
        );

        const rendered = vnode("div", {attrs: {}}, [
          Vdom.trustedHtmlVnode("<b>a</b>", null),
          Vdom.trustedHtmlVnode("<i>b</i>", null),
        ]);

        assert.throws(
          () => Vdom.mirror(rendered, container),
          HologramRuntimeError,
          "trusted HTML was moved by the browser's HTML parser",
        );
      });

      it("adopts table rows under a tbody parent without a warning", () => {
        const container = mount(
          "<table><tbody><!--hologram-html--><tr><td>1</td></tr><!--/hologram-html--></tbody></table>",
        );

        const rendered = vnode("div", {attrs: {}}, [
          vnode("table", {attrs: {}}, [
            vnode("tbody", {attrs: {}}, [
              Vdom.trustedHtmlVnode("<tr><td>1</td></tr>", null),
            ]),
          ]),
        ]);

        const cell = container.querySelector("td");

        patch(Vdom.mirror(rendered, container), rendered);

        assert.strictEqual(container.querySelector("td"), cell);
        sinon.assert.notCalled(warnStub);
      });

      it("adopts SVG content under an SVG parent without a warning", () => {
        const container = mount(
          '<svg><!--hologram-html--><path d="a"/><path d="b"/><!--/hologram-html--></svg>',
        );

        const rendered = vnode("div", {attrs: {}}, [
          vnode("svg", {attrs: {}}, [
            Vdom.trustedHtmlVnode('<path d="a"/><path d="b"/>', null),
          ]),
        ]);

        const path = container.querySelector("path");

        patch(Vdom.mirror(rendered, container), rendered);

        assert.strictEqual(container.querySelector("path"), path);
        sinon.assert.notCalled(warnStub);
      });

      it("creates a range whose start comment is gone, removing what's left of the old one", () => {
        const {container, patched} = adopt(
          [Vdom.trustedHtmlVnode("<b>b</b>", null)],
          "<b>b</b><!--/hologram-html-->",
        );

        patched();

        assert.equal(
          container.innerHTML,
          "<!--hologram-html--><b>b</b><!--/hologram-html-->",
        );
      });
    });
  });

  describe("patchModules", () => {
    const patch = init(Vdom.patchModules, Vdom.domApi);

    const create = (sel) => {
      const container = document.createElement("div");
      document.body.appendChild(container);

      const rendered = vnode("div", {attrs: {}}, [vnode(sel, {attrs: {}}, [])]);
      patch(container, rendered);

      return container.firstChild;
    };

    afterEach(() => {
      App.cspNonce = null;
    });

    it("sets the document's nonce on a created script element", () => {
      App.cspNonce = "my_nonce";

      assert.equal(create("script").nonce, "my_nonce");
    });

    it("sets the document's nonce on a created style element", () => {
      App.cspNonce = "my_nonce";

      assert.equal(create("style").nonce, "my_nonce");
    });

    it("sets the document's nonce on a created link element", () => {
      App.cspNonce = "my_nonce";

      assert.equal(create("link").nonce, "my_nonce");
    });

    it("sets no nonce on a created element of another kind", () => {
      App.cspNonce = "my_nonce";

      assert.equal(create("img").nonce, "");
    });

    it("sets no nonce when the document has none", () => {
      assert.equal(create("script").nonce, "");
    });

    describe("a created script", () => {
      const createScript = (hologramScript) => {
        const container = document.createElement("div");
        document.body.appendChild(container);

        const rendered = vnode("div", {attrs: {}}, [
          vnode("script", {attrs: {}, hologramScript}, []),
        ]);

        patch(container, rendered);

        return container.firstChild;
      };

      afterEach(() => {
        delete globalThis.trustedTypes;
        TrustedTypes.cachedPolicy = undefined;
      });

      it("gets its URL", () => {
        const script = createScript({code: null, src: "/app.js"});

        assert.equal(script.getAttribute("src"), "/app.js");
        assert.equal(script.textContent, "");
      });

      it("gets its code", () => {
        const script = createScript({code: "go();", src: null});

        assert.isFalse(script.hasAttribute("src"));
        assert.equal(script.textContent, "go();");
      });

      it("gets its code inside an SVG, whose script element has no text property", () => {
        const container = document.createElement("div");
        document.body.appendChild(container);

        const svgNs = "http://www.w3.org/2000/svg";

        const rendered = vnode("div", {attrs: {}}, [
          vnode("svg", {attrs: {}, ns: svgNs}, [
            vnode(
              "script",
              {
                attrs: {},
                hologramScript: {code: "go();", src: null},
                ns: svgNs,
              },
              [],
            ),
          ]),
        ]);

        patch(container, rendered);

        const script = container.querySelector("script");

        assert.equal(script.namespaceURI, svgNs);
        assert.equal(script.textContent, "go();");
      });

      it("gets its URL and code through the Trusted Types policy", () => {
        const assigned = [];

        TrustedTypes.cachedPolicy = undefined;

        globalThis.trustedTypes = {
          createPolicy: (_name, rules) => ({
            createScript: (code) => {
              assigned.push(["script", code]);
              return rules.createScript(code);
            },
            createScriptURL: (url) => {
              assigned.push(["scriptUrl", url]);
              return rules.createScriptURL(url);
            },
          }),
        };

        createScript({code: "go();", src: "/app.js"});

        assert.deepStrictEqual(assigned, [
          ["scriptUrl", "/app.js"],
          ["script", "go();"],
        ]);
      });
    });
  });

  describe("trusted HTML ranges", () => {
    const patch = init(Vdom.patchModules, Vdom.domApi);

    // Patches the given children into a fresh div in the document and returns the div, with a
    // function patching the next children in.
    const mount = (children, sel = "div") => {
      const container = document.createElement("div");
      document.body.appendChild(container);

      let current = patch(container, vnode(sel, {}, children));

      const update = (nextChildren) => {
        current = patch(current, vnode(sel, {}, nextChildren));
      };

      return {element: current.elm, update};
    };

    it("puts the HTML's nodes between the range comments", () => {
      const {element} = mount([
        vnode("p", {}, ["a"]),
        Vdom.trustedHtmlVnode("<b>b</b>"),
        vnode("p", {}, ["c"]),
      ]);

      assert.equal(
        element.innerHTML,
        "<p>a</p><!--hologram-html--><b>b</b><!--/hologram-html--><p>c</p>",
      );
    });

    it("rewrites the content when the HTML changes", () => {
      const {element, update} = mount([Vdom.trustedHtmlVnode("<b>a</b>")]);

      update([Vdom.trustedHtmlVnode("<i>b</i>")]);

      assert.equal(
        element.innerHTML,
        "<!--hologram-html--><i>b</i><!--/hologram-html-->",
      );
    });

    it("keeps the content's nodes when the HTML is the same", () => {
      const {element, update} = mount([Vdom.trustedHtmlVnode("<b>a</b>")]);
      const bold = element.querySelector("b");

      update([Vdom.trustedHtmlVnode("<b>a</b>")]);

      assert.strictEqual(element.querySelector("b"), bold);
    });

    it("moves the whole range when its place among keyed siblings changes", () => {
      const {element, update} = mount([
        Vdom.trustedHtmlVnode("<b>a</b><i>b</i>"),
        vnode("p", {key: "k"}, ["c"]),
      ]);

      update([
        vnode("p", {key: "k"}, ["c"]),
        Vdom.trustedHtmlVnode("<b>a</b><i>b</i>"),
      ]);

      assert.equal(
        element.innerHTML,
        "<p>c</p><!--hologram-html--><b>a</b><i>b</i><!--/hologram-html-->",
      );
    });

    it("moves a node to right after a range that ends the old children", () => {
      const {element, update} = mount([
        vnode("p", {key: "k"}, ["a"]),
        Vdom.trustedHtmlVnode("<b>b</b><i>c</i>"),
      ]);

      update([
        Vdom.trustedHtmlVnode("<b>b</b><i>c</i>"),
        vnode("p", {key: "k"}, ["a"]),
      ]);

      assert.equal(
        element.innerHTML,
        "<!--hologram-html--><b>b</b><i>c</i><!--/hologram-html--><p>a</p>",
      );
    });

    it("creates a keyed node right after a range", () => {
      const {element, update} = mount([
        vnode("p", {key: "a"}, ["a"]),
        Vdom.trustedHtmlVnode("<b>b</b><i>c</i>"),
        vnode("p", {key: "x"}, ["x"]),
      ]);

      update([
        vnode("p", {key: "x"}, ["x"]),
        Vdom.trustedHtmlVnode("<b>b</b><i>c</i>"),
        vnode("p", {key: "c"}, ["c"]),
      ]);

      assert.equal(
        element.innerHTML,
        "<p>x</p><!--hologram-html--><b>b</b><i>c</i><!--/hologram-html--><p>c</p>",
      );
    });

    it("moves the whole range left past a keyed sibling", () => {
      const {element, update} = mount([
        vnode("p", {key: "a"}, ["a"]),
        vnode("p", {key: "b"}, ["b"]),
        Vdom.trustedHtmlVnode("<b>c</b><i>d</i>"),
      ]);

      update([
        Vdom.trustedHtmlVnode("<b>c</b><i>d</i>"),
        vnode("p", {key: "b"}, ["b"]),
        vnode("p", {key: "a"}, ["a"]),
      ]);

      assert.equal(
        element.innerHTML,
        "<!--hologram-html--><b>c</b><i>d</i><!--/hologram-html--><p>b</p><p>a</p>",
      );
    });

    it("rewrites only the range when the HTML changes between siblings", () => {
      const {element, update} = mount([
        vnode("p", {}, ["a"]),
        Vdom.trustedHtmlVnode("<b>b</b>"),
        vnode("p", {}, ["c"]),
      ]);

      const [first, last] = element.querySelectorAll("p");

      update([
        vnode("p", {}, ["a"]),
        Vdom.trustedHtmlVnode("<i>x</i><i>y</i>"),
        vnode("p", {}, ["c"]),
      ]);

      assert.equal(
        element.innerHTML,
        "<p>a</p><!--hologram-html--><i>x</i><i>y</i><!--/hologram-html--><p>c</p>",
      );

      assert.strictEqual(element.querySelectorAll("p")[0], first);
      assert.strictEqual(element.querySelectorAll("p")[1], last);
    });

    it("rewrites table rows in the tbody context", () => {
      const {element, update} = mount(
        [vnode("tbody", {}, [Vdom.trustedHtmlVnode("<tr><td>a</td></tr>")])],
        "table",
      );

      update([
        vnode("tbody", {}, [Vdom.trustedHtmlVnode("<tr><td>b</td></tr>")]),
      ]);

      assert.equal(
        element.innerHTML,
        "<tbody><!--hologram-html--><tr><td>b</td></tr><!--/hologram-html--></tbody>",
      );
    });

    it("raises when a range lost its end comment", () => {
      const {element, update} = mount([Vdom.trustedHtmlVnode("<b>a</b>")]);

      element.lastChild.remove();

      assert.throws(
        () => update([]),
        HologramRuntimeError,
        "a trusted HTML range lost the comment it ends with, so something outside Hologram changed the page",
      );
    });

    it("removes the whole range", () => {
      const {element, update} = mount([
        vnode("p", {}, ["a"]),
        Vdom.trustedHtmlVnode("<b>b</b><i>c</i>"),
      ]);

      update([vnode("p", {}, ["a"])]);

      assert.equal(element.innerHTML, "<p>a</p>");
    });

    it("inserts a node before a range", () => {
      const {element, update} = mount([Vdom.trustedHtmlVnode("<b>b</b>")]);

      update([vnode("p", {}, ["a"]), Vdom.trustedHtmlVnode("<b>b</b>")]);

      assert.equal(
        element.innerHTML,
        "<p>a</p><!--hologram-html--><b>b</b><!--/hologram-html-->",
      );
    });

    it("inserts a node after a range", () => {
      const {element, update} = mount([Vdom.trustedHtmlVnode("<b>b</b>")]);

      update([Vdom.trustedHtmlVnode("<b>b</b>"), vnode("p", {}, ["c"])]);

      assert.equal(
        element.innerHTML,
        "<!--hologram-html--><b>b</b><!--/hologram-html--><p>c</p>",
      );
    });

    it("parses SVG content under an SVG parent", () => {
      const {element} = mount(
        [Vdom.trustedHtmlVnode('<path d="a"/><path d="b"/>')],
        "svg",
      );

      const paths = element.querySelectorAll("path");

      assert.equal(paths.length, 2);
      assert.strictEqual(paths[0].parentNode, element);
      assert.equal(paths[1].namespaceURI, "http://www.w3.org/2000/svg");
    });

    it("parses table rows under a tbody parent", () => {
      const {element} = mount(
        [vnode("tbody", {}, [Vdom.trustedHtmlVnode("<tr><td>a</td></tr>")])],
        "table",
      );

      assert.equal(
        element.innerHTML,
        "<tbody><!--hologram-html--><tr><td>a</td></tr><!--/hologram-html--></tbody>",
      );
    });

    it("adds the tbody the browser adds to rows under a table parent", () => {
      const {element} = mount(
        [Vdom.trustedHtmlVnode("<tr><td>a</td></tr>")],
        "table",
      );

      assert.equal(
        element.innerHTML,
        "<!--hologram-html--><tbody><tr><td>a</td></tr></tbody><!--/hologram-html-->",
      );
    });
  });

  describe("parseTrustedHtml()", () => {
    const parse = (html, parent = document.createElement("div")) =>
      Vdom.parseTrustedHtml(html, parent);

    const serialize = (nodes) => {
      const container = document.createElement("div");
      container.append(...nodes);

      return container.innerHTML;
    };

    it("closes unclosed elements", () => {
      assert.equal(serialize(parse("<div><b>bold")), "<div><b>bold</b></div>");
    });

    it("removes script, plaintext and noscript elements at any depth", () => {
      const html =
        "<p>a<script>1</script></p><noscript>b</noscript><div><plaintext>c</div>";

      assert.equal(serialize(parse(html)), "<p>a</p><div></div>");
    });

    it("removes SVG script elements", () => {
      assert.equal(
        serialize(parse("<svg><script>1</script><circle></circle></svg>")),
        "<svg><circle></circle></svg>",
      );
    });

    it("removes comments carrying a range marker and keeps other comments", () => {
      const html =
        "a<!--hologram-html-->b<!--/hologram-html-->c<!-- keep --><p><!--hologram-html--></p>";

      assert.equal(serialize(parse(html)), "abc<!-- keep --><p></p>");
    });

    it("merges the text a removed node separated", () => {
      const nodes = parse("a<script>1</script>b");

      assert.equal(nodes.length, 1);
      assert.equal(nodes[0].data, "ab");
    });

    it("removes the shadowroot attributes of template elements", () => {
      const html =
        '<template id="t" shadowrootmode="open" shadowrootdelegatesfocus><p>a</p></template>';

      const [template] = parse(html);

      assert.deepStrictEqual(template.getAttributeNames(), ["id"]);
    });

    it("removes what the server removes in a template nested in template contents", () => {
      const [outer] = parse(
        '<template><template shadowrootmode="open"><script>1</script>a</template></template>',
      );

      const inner = outer.content.firstChild;

      assert.deepStrictEqual(inner.getAttributeNames(), []);
      assert.equal(inner.content.textContent, "a");
      assert.equal(inner.content.childNodes.length, 1);
    });

    it("parses through the Trusted Types policy", () => {
      const created = [];

      globalThis.trustedTypes = {
        createPolicy: (_name, rules) => ({
          createHTML: (html) => {
            created.push(html);
            return rules.createHTML(html);
          },
          createScript: rules.createScript,
          createScriptURL: rules.createScriptURL,
        }),
      };

      TrustedTypes.cachedPolicy = undefined;

      try {
        parse("<b>a</b>");
      } finally {
        delete globalThis.trustedTypes;
        TrustedTypes.cachedPolicy = undefined;
      }

      assert.deepStrictEqual(created, ["<b>a</b>"]);
    });

    it("removes what the server removes inside template contents", () => {
      const nodes = parse(
        "<template><script>1</script>a<!--hologram-html-->b</template>",
      );
      const content = nodes[0].content;

      assert.equal(content.childNodes.length, 1);
      assert.equal(content.textContent, "ab");
    });

    it("leaves an SVG element named template alone", () => {
      assert.equal(
        serialize(parse("<svg><template><circle></circle></template></svg>")),
        "<svg><template><circle></circle></template></svg>",
      );
    });

    it("parses in the context of a template parent", () => {
      const nodes = parse(
        "<tr><td>a</td></tr>",
        document.createElement("template"),
      );

      assert.equal(serialize(nodes), "<tr><td>a</td></tr>");
    });

    it("parses in the context of a parent with no element", () => {
      assert.equal(serialize(parse("<p>a</p>", null)), "<p>a</p>");
    });

    it("keeps the encoding of an annotation-xml parent", () => {
      const parent = document.createElementNS(
        "http://www.w3.org/1998/Math/MathML",
        "annotation-xml",
      );

      parent.setAttribute("encoding", "text/html");

      const [style] = parse("<style>a>b</style>", parent);

      assert.equal(style.namespaceURI, "http://www.w3.org/1999/xhtml");
    });

    it("parses in MathML context under an annotation-xml parent without an HTML encoding", () => {
      const parent = document.createElementNS(
        "http://www.w3.org/1998/Math/MathML",
        "annotation-xml",
      );

      const [mi] = parse("<mi>x</mi>", parent);

      assert.equal(mi.namespaceURI, "http://www.w3.org/1998/Math/MathML");
    });
  });
});
