"use strict";

import Bitstring2 from "../../../../../../assets/js/bitstring2.mjs";
import Type from "../../../../../../assets/js/type.mjs";

import {benchmark} from "../../../../support/helpers.mjs";

const bitstring = Type.bitstring2("全息图全息图全息图全");

Bitstring2.maybeSetBytesFromText(bitstring);

benchmark(() => {
  let binaryString = "";

  for (let i = 0; i < bitstring.bytes.length; i++) {
    binaryString += String.fromCharCode(bitstring.bytes[i]);
  }

  btoa(binaryString);
});
