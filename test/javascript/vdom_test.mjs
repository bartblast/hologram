"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  registerWebApis,
  vnode,
} from "./support/helpers.mjs";

import Vdom from "../../assets/js/vdom.mjs";

defineGlobalErlangAndElixirModules();
registerWebApis();

describe("Vdom", () => {
  describe("addKeysToScriptVnodes()", () => {
    it("element node that is not a script", () => {
      const node = vnode("img", {attrs: {src: "my_source"}}, []);
      Vdom.addKeysToScriptVnodes(node);

      assert.deepStrictEqual(
        node,
        vnode("img", {attrs: {src: "my_source"}}, []),
      );
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

      Vdom.addKeysToScriptVnodes(node);

      assert.deepStrictEqual(node, {
        sel: undefined,
        data: undefined,
        children: undefined,
        text: "my_text",
        elm: undefined,
        key: undefined,
      });
    });

    it("script element without attrs field", () => {
      const node = vnode("script", {}, []);
      Vdom.addKeysToScriptVnodes(node);

      assert.deepStrictEqual(node, vnode("script", {}, []));
    });

    it("script element without src attribute (inline script), but with some other attribute", () => {
      const node = vnode("script", {attrs: {type: "text/javascript"}}, []);
      Vdom.addKeysToScriptVnodes(node);

      assert.deepStrictEqual(
        node,
        vnode("script", {attrs: {type: "text/javascript"}}, []),
      );
    });

    it("script element with boolean src attribute", () => {
      const node = vnode("script", {attrs: {src: true}}, []);
      Vdom.addKeysToScriptVnodes(node);

      assert.deepStrictEqual(node, vnode("script", {attrs: {src: true}}, []));
    });

    it("script element with non-empty string src attribute", () => {
      const node = vnode("script", {attrs: {src: "my_script"}}, []);
      Vdom.addKeysToScriptVnodes(node);

      assert.deepStrictEqual(
        node,
        vnode(
          "script",
          {
            key: "__hologramScript__:my_script",
            attrs: {src: "my_script"},
          },
          [],
        ),
      );
    });

    it("nested script nodes", () => {
      const node = vnode("div", {}, [
        vnode("script", {attrs: {src: "my_script_1"}}, []),
        vnode("img", {attrs: {src: "my_source"}}, []),
        vnode("script", {attrs: {src: "my_script_2"}}, []),
      ]);

      Vdom.addKeysToScriptVnodes(node);

      assert.deepStrictEqual(
        node,
        vnode("div", {}, [
          vnode(
            "script",
            {
              key: "__hologramScript__:my_script_1",
              attrs: {src: "my_script_1"},
            },
            [],
          ),
          vnode("img", {attrs: {src: "my_source"}}, []),
          vnode(
            "script",
            {
              key: "__hologramScript__:my_script_2",
              attrs: {src: "my_script_2"},
            },
            [],
          ),
        ]),
      );
    });
  });

  describe("from()", () => {
    it("builds virtual DOM from HTML markup", () => {
      const html =
        '<!DOCTYPE html><html lang="en"><head></head><body><div attr1="abc" attr2></div><!-- my comment --><span>abc</span></body></html>';

      const result = Vdom.from(html);

      const expected = vnode("html", {attrs: {lang: "en"}}, [
        vnode("head", {attrs: {}}, []),
        vnode("body", {attrs: {}}, [
          vnode("div", {attrs: {attr1: "abc", attr2: true}}, []),
          vnode("!", " my comment "),
          vnode("span", {attrs: {}}, ["abc"]),
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    describe("script element vnode key", () => {
      it("not a script element", () => {
        const result = Vdom.from(
          '<html><body><img src="my_source" /></body></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, []),
          vnode("body", {attrs: {}}, [
            vnode("img", {attrs: {src: "my_source"}}, []),
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
          '<html><head><script src="my_source"></script></head></html>',
        );

        const expected = vnode("html", {attrs: {}}, [
          vnode("head", {attrs: {}}, [
            vnode(
              "script",
              {key: "__hologramScript__:my_source", attrs: {src: "my_source"}},
              [],
            ),
          ]),
          vnode("body", {attrs: {}}, []),
        ]);

        assert.deepStrictEqual(result, expected);
      });
    });
  });
});
