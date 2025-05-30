"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";

import {
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "../../../../../test/javascript/support/helpers.mjs";

defineGlobalErlangAndElixirModules();

const context = contextFixture();

benchmark(() => {
  try {
    Interpreter.matchOperator(Type.atom("abc"), Type.atom("xyz"), context);
  } catch {}
});
