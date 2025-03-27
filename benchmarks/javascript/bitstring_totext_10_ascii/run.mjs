"use strict";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Type from "../../../assets/js/type.mjs";

import {benchmark} from "../support/helpers.mjs";

const bitstring = Type.bitstring("abcdefghij");

benchmark(() => {
  Bitstring.toText(bitstring);
});
