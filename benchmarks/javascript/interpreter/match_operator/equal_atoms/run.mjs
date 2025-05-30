"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";
import {contextFixture} from "../../../../../test/javascript/support/helpers.mjs";

const context = contextFixture();

benchmark(() => {
  Interpreter.matchOperator(Type.atom("abc"), Type.atom("abc"), context);
});
