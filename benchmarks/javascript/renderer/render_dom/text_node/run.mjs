"use strict";

import Renderer from "../../../../../assets/js/renderer.mjs";
import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";
import {defineGlobalErlangAndElixirModules} from "../../../../../test/javascript/support/helpers.mjs";

defineGlobalErlangAndElixirModules();

const context = Type.map();
const defaultTarget = Type.bitstring("my_default_target");
const slots = Type.keywordList();
const node = Type.tuple([Type.atom("text"), Type.bitstring("abc")]);

benchmark(() => {
  Renderer.renderDom(node, context, slots, defaultTarget);
});
