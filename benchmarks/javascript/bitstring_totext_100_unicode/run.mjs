"use strict";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Type from "../../../assets/js/type.mjs";

import {benchmark} from "../support/helpers.mjs";

const bitstring = Type.bitstring(
  "全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全",
);

benchmark(() => {
  Bitstring.toText(bitstring);
});
