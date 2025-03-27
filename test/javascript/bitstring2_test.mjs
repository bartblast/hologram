"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Bitstring2 from "../../assets/js/bitstring2.mjs";

defineGlobalErlangAndElixirModules();

describe("Bitstring2", () => {
  it("fromText()", () => {
    const result = Bitstring2.fromText("Hologram");

    const expected = {
      type: "bitstring",
      text: "Hologram",
      bits: null,
      isByteAligned: true,
      numLeftoverBits: 0,
    };

    assert.deepStrictEqual(result, expected);
  });
});
