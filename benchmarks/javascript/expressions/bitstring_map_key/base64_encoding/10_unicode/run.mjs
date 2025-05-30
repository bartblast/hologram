"use strict";

import Bitstring from "../../../../../../assets/js/bitstring.mjs";
import Type from "../../../../../../assets/js/type.mjs";

import {benchmark} from "../../../../support/helpers.mjs";

const bitstring = Type.bitstring("全息图全息图全息图全");

Bitstring.maybeSetBytesFromText(bitstring);

benchmark(() => {
  let binaryString = "";

  for (let i = 0; i < bitstring.bytes.length; i++) {
    binaryString += String.fromCharCode(bitstring.bytes[i]);
  }

  btoa(binaryString);
});
