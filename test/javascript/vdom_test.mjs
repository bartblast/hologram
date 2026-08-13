"use strict";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  vnode,
} from "./support/helpers.mjs";

import Vdom from "../../assets/js/vdom.mjs";

defineRuntimeGlobals();
registerWebApis();

describe("Vdom", () => {
  describe("addKeysToVnodes()", () => {
    it("element node that is not a link or script", () => {
      const node = vnode("img", {attrs: {src: "my_src"}}, []);
      Vdom.addKeysToVnodes(node);

      assert.deepStrictEqual(node, vnode("img", {attrs: {src: "my_src"}}, []));
    });

    it("text node", () => {
      const node = {
        sel: undefined,
        data: undefined,
        children: undefined,
        text: "my_text",
        elm: undefined,
        key: undefined,
      };

      Vdom.addKeysToVnodes(node);

      assert.deepStrictEqual(node, {
        sel: undefined,
        data: undefined,
        children: undefined,
        text: "my_text",
        elm: undefined,
        key: undefined,
      });
    });

    describe("comment node", () => {
      it("ordinary comment", () => {
        const node = vnode("!", "my comment");
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(node, vnode("!", "my comment"));
      });

      it("opening block marker", () => {
        const node = vnode("!", "[h:1a2b3c:0:o]");
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        );
      });

      it("closing block marker", () => {
        const node = vnode("!", "[h:1a2b3c:0:c]");
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode("!", {key: "[h:1a2b3c:0:c]"}, "[h:1a2b3c:0:c]"),
        );
      });

      it("nested block markers", () => {
        const node = vnode("div", {}, [
          vnode("!", "[h:1a2b3c:0:o]"),
          vnode("img", {attrs: {src: "my_src"}}, []),
          vnode("!", "[h:1a2b3c:0:c]"),
        ]);

        Vdom.addKeysToVnodes(node);

        // The marked span is gathered into one keyed fragment.
        assert.equal(node.children.length, 1);

        const blockFragment = node.children[0];

        assert.isUndefined(blockFragment.sel);
        assert.equal(blockFragment.key, "[h:1a2b3c:0:o]");

        assert.deepStrictEqual(
          blockFragment.children.map((child) => child.key ?? child.sel),
          ["[h:1a2b3c:0:o]", "img", "[h:1a2b3c:0:c]"],
        );
      });
    });

    describe("link element", () => {
      it("without attrs field", () => {
        const node = vnode("link", {}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(node, vnode("link", {}, []));
      });

      it("without href attribute, but with some other attribute", () => {
        const node = vnode("link", {attrs: {rel: "stylesheet"}}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode("link", {attrs: {rel: "stylesheet"}}, []),
        );
      });

      it("with boolean href attribute", () => {
        const node = vnode("link", {attrs: {href: true}}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(node, vnode("link", {attrs: {href: true}}, []));
      });

      it("with non-empty string href attribute", () => {
        const node = vnode("link", {attrs: {href: "my_link"}}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode(
            "link",
            {
              key: "__hologramLink__:my_link",
              attrs: {href: "my_link"},
            },
            [],
          ),
        );
      });

      it("nested link nodes", () => {
        const node = vnode("div", {}, [
          vnode("link", {attrs: {href: "my_link_1"}}, []),
          vnode("img", {attrs: {src: "my_src"}}, []),
          vnode("link", {attrs: {href: "my_link_2"}}, []),
        ]);

        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode("div", {}, [
            vnode(
              "link",
              {
                key: "__hologramLink__:my_link_1",
                attrs: {href: "my_link_1"},
              },
              [],
            ),
            vnode("img", {attrs: {src: "my_src"}}, []),
            vnode(
              "link",
              {
                key: "__hologramLink__:my_link_2",
                attrs: {href: "my_link_2"},
              },
              [],
            ),
          ]),
        );
      });
    });

    describe("script element", () => {
      it("without attrs field", () => {
        const node = vnode("script", {}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(node, vnode("script", {}, []));
      });

      it("without src attribute (inline script), but with some other attribute", () => {
        const node = vnode("script", {attrs: {type: "text/javascript"}}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode("script", {attrs: {type: "text/javascript"}}, []),
        );
      });

      it("with boolean src attribute", () => {
        const node = vnode("script", {attrs: {src: true}}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(node, vnode("script", {attrs: {src: true}}, []));
      });

      it("with non-empty string src attribute", () => {
        const node = vnode("script", {attrs: {src: "my_src"}}, []);
        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode(
            "script",
            {
              key: "__hologramScript__:my_src",
              attrs: {src: "my_src"},
            },
            [],
          ),
        );
      });

      it("nested script nodes", () => {
        const node = vnode("div", {}, [
          vnode("script", {attrs: {src: "my_src_1"}}, []),
          vnode("img", {attrs: {src: "my_src"}}, []),
          vnode("script", {attrs: {src: "my_src_2"}}, []),
        ]);

        Vdom.addKeysToVnodes(node);

        assert.deepStrictEqual(
          node,
          vnode("div", {}, [
            vnode(
              "script",
              {
                key: "__hologramScript__:my_src_1",
                attrs: {src: "my_src_1"},
              },
              [],
            ),
            vnode("img", {attrs: {src: "my_src"}}, []),
            vnode(
              "script",
              {
                key: "__hologramScript__:my_src_2",
                attrs: {src: "my_src_2"},
              },
              [],
            ),
          ]),
        );
      });
    });
  });

  describe("dedupeMarkerKeys()", () => {
    it("distinct marker keys", () => {
      const children = [
        vnode("!", {key: "[h:1a2b3c:0:o]"}, "[h:1a2b3c:0:o]"),
        vnode("!", {key: "[h:1a2b3c:0:c]"}, "[h:1a2b3c:0:c]"),
      ];

      Vdom.dedupeMarkerKeys(children);

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

      Vdom.dedupeMarkerKeys(children);

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

      Vdom.dedupeMarkerKeys(children);

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

      Vdom.dedupeMarkerKeys(children);

      assert.deepStrictEqual(
        children.map((child) => child.key),
        [undefined, undefined, undefined, undefined],
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
  });

  describe("from()", () => {
    it("builds virtual DOM from HTML markup", () => {
      const html =
        '<!DOCTYPE html><html lang="en" class="abc"><head></head><body><div attr1="abc" attr2></div><!-- my comment --><span>abc</span></body></html>';

      const result = Vdom.from(html);

      const expected = vnode("html", {attrs: {lang: "en", class: "abc"}}, [
        vnode("head", {attrs: {}}, []),
        vnode("body", {attrs: {}}, [
          vnode("div", {attrs: {attr1: "abc", attr2: true}}, []),
          vnode("!", " my comment "),
          vnode("span", {attrs: {}}, ["abc"]),
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("numbers repeated block marker comments", () => {
      const result = Vdom.from(
        "<html><body><!--[h:1a2b3c:0:o]--><!--[h:1a2b3c:0:o]--></body></html>",
      );

      const body = result.children[1];

      assert.deepStrictEqual(
        body.children.map((child) => child.key),
        ["[h:1a2b3c:0:o]", "[h:1a2b3c:0:o]:1"],
      );
    });

    it("keys block marker comments", () => {
      const result = Vdom.from(
        "<html><body><!--[h:1a2b3c:0:o]--><!-- my comment --><!--[h:1a2b3c:0:c]--></body></html>",
      );

      const body = result.children[1];

      assert.equal(body.children.length, 1);

      const blockFragment = body.children[0];

      assert.equal(blockFragment.key, "[h:1a2b3c:0:o]");

      assert.deepStrictEqual(
        blockFragment.children.map((child) => child.key ?? child.text),
        ["[h:1a2b3c:0:o]", " my comment ", "[h:1a2b3c:0:c]"],
      );
    });

    describe("link element vnode key", () => {
      it("not a link element", () => {
        const result = Vdom.from(
          '<html><body><a href="my_href"></a></body></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, []),
          vnode("body", {attrs: {}}, [
            vnode("a", {attrs: {href: "my_href"}}, []),
          ]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("link element without href attribute", () => {
        const result = Vdom.from(
          '<html><head><link ref="stylesheet" /></head></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode("link", {attrs: {ref: "stylesheet"}}, []),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("link element with empty string href attribute", () => {
        const result = Vdom.from('<html><head><link href="" /></head></html>');

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode("link", {attrs: {href: true}}, []),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("link element with boolean href attribute", () => {
        const result = Vdom.from("<html><head><link href /></head></html>");

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode("link", {attrs: {href: true}}, []),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("link element with non-empty href attribute", () => {
        const result = Vdom.from(
          '<html><head><link href="my_href" /></head></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode(
              "link",
              {key: "__hologramLink__:my_href", attrs: {href: "my_href"}},
              [],
            ),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("script element vnode key", () => {
      it("not a script element", () => {
        const result = Vdom.from(
          '<html><body><img src="my_src" /></body></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, []),
          vnode("body", {attrs: {}}, [
            vnode("img", {attrs: {src: "my_src"}}, []),
          ]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("script element without src attribute (inline script)", () => {
        const result = Vdom.from(
          '<html><head><script type="text/html"></script></head></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode("script", {attrs: {type: "text/html"}}, []),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("script element with empty string src attribute", () => {
        const result = Vdom.from(
          '<html><head><script src=""></script></head></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode("script", {attrs: {src: true}}, []),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("script element with boolean src attribute", () => {
        const result = Vdom.from(
          "<html><head><script src></script></head></html>",
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode("script", {attrs: {src: true}}, []),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("script element with non-empty src attribute", () => {
        const result = Vdom.from(
          '<html><head><script src="my_src"></script></head></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode(
              "script",
              {key: "__hologramScript__:my_src", attrs: {src: "my_src"}},
              [],
            ),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("script element with non-empty text content", () => {
        const result = Vdom.from(
          "<html><head><script>const x = 123;</script></head></html>",
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode(
              "script",
              {key: "__hologramScript__:const x = 123;", attrs: {}},
              ["const x = 123;"],
            ),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("script element with empty text content", () => {
        const result = Vdom.from("<html><head><script></script></head></html>");

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [vnode("script", {attrs: {}}, [])]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });
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

      Vdom.dedupeMarkerKeys(children);

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

      Vdom.dedupeMarkerKeys(children);

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

      Vdom.dedupeMarkerKeys(children);

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
});
