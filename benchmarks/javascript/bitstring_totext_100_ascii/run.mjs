"use strict";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Type from "../../../assets/js/type.mjs";

import {benchmark} from "../support/helpers.mjs";

const bitstring = Type.bitstring(
  "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij",
);

benchmark(() => {
  Bitstring.toText(bitstring);
});
