"use strict";

export default class Bitstring2 {
  static fromText(text) {
    return {
      type: "bitstring",
      text: text,
      bits: null,
      isByteAligned: true,
      numLeftoverBits: 0,
    };
  }
}
