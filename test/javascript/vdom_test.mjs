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
  it("from()", () => {
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
});
