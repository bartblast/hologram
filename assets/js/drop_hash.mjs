"use strict";

// The hash a server names a row by when it tells a client to drop it without telling it the row's
// id - the client finds the rows it holds whose ids hash to one it was sent, and nothing else.
// Hologram.Sync.Frame.drop_hash/2 works out the same one: the first 64 bits of the SHA-256 of the
// salt followed by the id, as 16 lowercase hex digits.
//
// Worked out here rather than through the browser's own SubtleCrypto, which only answers through a
// promise: a frame is applied in one go, and one frame can ask for the hashes of every row of a type
// the client holds. Ids and salts are ASCII, so each character's code is the byte the server
// hashes.
const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

const INITIAL = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
  0x1f83d9ab, 0x5be0cd19,
];

export default class DropHash {
  static hash(salt, id) {
    const [first, second] = DropHash.#sha256(salt + id);

    return DropHash.#hex(first) + DropHash.#hex(second);
  }

  static #hex(word) {
    return (word >>> 0).toString(16).padStart(8, "0");
  }

  static #rotate(word, bits) {
    return (word >>> bits) | (word << (32 - bits));
  }

  // The message padded as SHA-256 pads it: a 1 bit, zeros, and the length in bits, to a whole
  // number of 64-byte blocks.
  static #blocks(text) {
    const length = text.length;
    const size = Math.ceil((length + 9) / 64) * 64;
    const bytes = new Uint8Array(size);

    for (let index = 0; index < length; index++) {
      bytes[index] = text.charCodeAt(index);
    }

    bytes[length] = 0x80;

    const view = new DataView(bytes.buffer);
    view.setUint32(size - 8, Math.floor((length * 8) / 0x100000000));
    view.setUint32(size - 4, (length * 8) >>> 0);

    return view;
  }

  static #sha256(text) {
    const view = DropHash.#blocks(text);
    const state = INITIAL.slice();
    const words = new Uint32Array(64);

    for (let offset = 0; offset < view.byteLength; offset += 64) {
      for (let index = 0; index < 16; index++) {
        words[index] = view.getUint32(offset + index * 4);
      }

      for (let index = 16; index < 64; index++) {
        const before = words[index - 15];
        const later = words[index - 2];

        const s0 =
          DropHash.#rotate(before, 7) ^
          DropHash.#rotate(before, 18) ^
          (before >>> 3);

        const s1 =
          DropHash.#rotate(later, 17) ^
          DropHash.#rotate(later, 19) ^
          (later >>> 10);

        words[index] = (words[index - 16] + s0 + words[index - 7] + s1) | 0;
      }

      let [a, b, c, d, e, f, g, h] = state;

      for (let index = 0; index < 64; index++) {
        const s1 =
          DropHash.#rotate(e, 6) ^
          DropHash.#rotate(e, 11) ^
          DropHash.#rotate(e, 25);

        const choice = (e & f) ^ (~e & g);
        const first = (h + s1 + choice + K[index] + words[index]) | 0;

        const s0 =
          DropHash.#rotate(a, 2) ^
          DropHash.#rotate(a, 13) ^
          DropHash.#rotate(a, 22);

        const majority = (a & b) ^ (a & c) ^ (b & c);
        const second = (s0 + majority) | 0;

        h = g;
        g = f;
        f = e;
        e = (d + first) | 0;
        d = c;
        c = b;
        b = a;
        a = (first + second) | 0;
      }

      state[0] = (state[0] + a) | 0;
      state[1] = (state[1] + b) | 0;
      state[2] = (state[2] + c) | 0;
      state[3] = (state[3] + d) | 0;
      state[4] = (state[4] + e) | 0;
      state[5] = (state[5] + f) | 0;
      state[6] = (state[6] + g) | 0;
      state[7] = (state[7] + h) | 0;
    }

    return state;
  }
}
