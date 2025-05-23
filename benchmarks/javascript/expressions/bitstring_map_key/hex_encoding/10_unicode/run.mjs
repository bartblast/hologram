"use strict";

import Bitstring2 from "../../../../../../assets/js/bitstring2.mjs";
import Type from "../../../../../../assets/js/type.mjs";

import {benchmark} from "../../../../support/helpers.mjs";

const bitstring = Type.bitstring2("全息图全息图全息图全");

Bitstring2.maybeSetBytesFromText(bitstring);

benchmark(() => {
  let _hexString = "";

  for (let i = 0; i < bitstring.bytes.length; i++) {
    _hexString += bitstring.bytes[i].toString(16).padStart(2, "0");
  }
});
