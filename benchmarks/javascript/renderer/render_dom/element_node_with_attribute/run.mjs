"use strict";

import Renderer from "../../../../../assets/js/renderer.mjs";
import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";
import {defineGlobalErlangAndElixirModules} from "../../../../../test/javascript/support/helpers.mjs";

defineGlobalErlangAndElixirModules();

const context = Type.map();
const defaultTarget = Type.bitstring("my_default_target");
const slots = Type.keywordList();

const node = Type.tuple([
  Type.atom("element"),
  Type.bitstring("div"),
  Type.list([
    Type.tuple([
      Type.bitstring("attr"),
      Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
    ]),
  ]),
  Type.list(),
]);

benchmark(() => {
  Renderer.renderDom(node, context, slots, defaultTarget);
});
