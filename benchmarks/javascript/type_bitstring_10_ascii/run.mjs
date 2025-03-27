"use strict";

import Type from "../../../assets/js/type.mjs";

import {benchmark} from "../support/helpers.mjs";

benchmark(() => {
  Type.bitstring("abcdefghij");
});
