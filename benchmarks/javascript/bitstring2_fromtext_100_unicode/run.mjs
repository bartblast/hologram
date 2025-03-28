"use strict";

import Bitstring2 from "../../../assets/js/bitstring2.mjs";

import {benchmark} from "../support/helpers.mjs";

const text =
  "全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全全息图全息图全息图全";

benchmark(() => {
  Bitstring2.fromText(text);
});
