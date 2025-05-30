"use strict";

import Type from "../../../../../assets/js/type.mjs";

import {benchmark} from "../../../support/helpers.mjs";

import isEqual from "../../../../../assets/node_modules/lodash/isEqual.js";

benchmark(() => {
  isEqual(Type.atom("abc"), Type.atom("abc"));
});
