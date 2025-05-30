"use strict";

import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";

import isEqual from "../../../../../assets/node_modules/lodash/isEqual.js";

const atom1 = Type.atom("abc");
const atom2 = Type.atom("xyz");

benchmark(() => {
  isEqual(atom1, atom2);
});
