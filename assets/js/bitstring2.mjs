"use strict";

export default class Bitstring2 {
  static fromBits(bits) {
    const length = bits.length;
    const byteCount = Math.ceil(length / 8);
    const numLeftoverBits = length % 8;
    const bytes = new Uint8Array(byteCount);

    // Process 8 bytes at a time when possible
    let byteIndex = 0;
    let bitIndex = 0;

    // Fast path for byte-aligned chunks
    while (bitIndex + 8 <= length) {
      bytes[byteIndex++] =
        (bits[bitIndex] << 7) |
        (bits[bitIndex + 1] << 6) |
        (bits[bitIndex + 2] << 5) |
        (bits[bitIndex + 3] << 4) |
        (bits[bitIndex + 4] << 3) |
        (bits[bitIndex + 5] << 2) |
        (bits[bitIndex + 6] << 1) |
        bits[bitIndex + 7];
      bitIndex += 8;
    }

    // Handle remaining bits if any
    if (bitIndex < length) {
      let lastByte = 0;

      for (let j = 0; j < numLeftoverBits; j++) {
        if (bits[bitIndex + j]) {
          lastByte |= 1 << (7 - j);
        }
      }
      bytes[byteIndex] = lastByte;
    }

    return {type: "bitstring", text: null, bytes, numLeftoverBits};
  }

  static fromText(text) {
    return {
      type: "bitstring",
      text: text,
      bytes: null,
      numLeftoverBits: 0,
    };
  }
}
