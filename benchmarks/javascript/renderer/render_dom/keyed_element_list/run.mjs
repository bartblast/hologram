"use strict";

import Renderer from "../../../../../assets/js/renderer.mjs";
import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";
import {defineRuntimeGlobals} from "../../../../../test/javascript/support/helpers.mjs";

defineRuntimeGlobals();

const ITEM_COUNT = 100;

const context = Type.map();
const defaultTarget = Type.bitstring("my_default_target");
const slots = Type.keywordList();

const textAttr = (name, value) =>
  Type.tuple([
    Type.bitstring(name),
    Type.keywordList([[Type.atom("text"), Type.bitstring(value)]]),
  ]);

// One item as a template renders it: the attributes the author wrote, then the key the compiler
// appended. The keys repeat the way a loop's do, so the list also exercises the numbering.
const item = (index) =>
  Type.tuple([
    Type.atom("element"),
    Type.bitstring("li"),
    Type.list([
      textAttr("class", "my_class"),
      textAttr("id", `my_id_${index}`),
      textAttr("$key", `1a2b3c:${index % 3}`),
    ]),
    Type.list([Type.tuple([Type.atom("text"), Type.bitstring("abc")])]),
  ]);

const node = Type.tuple([
  Type.atom("element"),
  Type.bitstring("ul"),
  Type.list([textAttr("$key", "1a2b3c:9")]),
  Type.list(Array.from({length: ITEM_COUNT}, (_value, index) => item(index))),
]);

benchmark(() => {
  Renderer.renderDom(node, context, slots, defaultTarget);
});
