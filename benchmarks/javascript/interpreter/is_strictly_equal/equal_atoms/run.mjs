"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";

const atom1 = Type.atom("abc");
const atom2 = Type.atom("abc");

benchmark(() => {
  Interpreter.isStrictlyEqual(atom1, atom2);
});
