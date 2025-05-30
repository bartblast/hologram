"use strict";

import Bitstring from "../../../../../../assets/js/bitstring.mjs";
import Type from "../../../../../../assets/js/type.mjs";

import {benchmark} from "../../../../support/helpers.mjs";

const bitstring = Type.bitstring(
  "全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全",
);

Bitstring.maybeSetBytesFromText(bitstring);

benchmark(() => {
  let _hexString = "";

  for (let i = 0; i < bitstring.bytes.length; i++) {
    _hexString += bitstring.bytes[i].toString(16).padStart(2, "0");
  }
});
