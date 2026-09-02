"use strict";

// A synchronous SHA-1 over bytes, written out rather than asked of the platform: the browser's
// own digest, crypto.subtle.digest, is async, and the one caller here derives a grant's id
// inside an action, which cannot await. RFC 3174 - pinned against its own test vectors in
// test/javascript/sha1_test.mjs, and against :crypto.hash(:sha, _) on the server through the
// grant id vectors both tiers hold (test/javascript/elixir/hologram/auth_test.mjs).
//
// Only where a standard mandates it: everywhere else the house digest is SHA-256.
export default class Sha1 {
  // Answers the 20-byte digest of the given Uint8Array.
  static digest(bytes) {
    const length = bytes.length;
    const paddedLength = Math.ceil((length + 1 + 8) / 64) * 64;
    const message = new Uint8Array(paddedLength);
    const view = new DataView(message.buffer);

    message.set(bytes);
    message[length] = 0x80;

    // The bit length, big-endian, in the last eight bytes. A JS number carries it exactly up to
    // 2^53 bits, which no input here approaches.
    const bitLength = length * 8;
    view.setUint32(paddedLength - 8, Math.floor(bitLength / 2 ** 32), false);
    view.setUint32(paddedLength - 4, bitLength >>> 0, false);

    let h0 = 0x67452301;
    let h1 = 0xefcdab89;
    let h2 = 0x98badcfe;
    let h3 = 0x10325476;
    let h4 = 0xc3d2e1f0;

    const words = new Uint32Array(80);

    for (let offset = 0; offset < paddedLength; offset += 64) {
      for (let i = 0; i < 16; i++) {
        words[i] = view.getUint32(offset + i * 4, false);
      }

      for (let i = 16; i < 80; i++) {
        words[i] = Sha1.#rotateLeft(
          words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16],
          1,
        );
      }

      let a = h0;
      let b = h1;
      let c = h2;
      let d = h3;
      let e = h4;

      for (let i = 0; i < 80; i++) {
        let f;
        let k;

        if (i < 20) {
          f = (b & c) | (~b & d);
          k = 0x5a827999;
        } else if (i < 40) {
          f = b ^ c ^ d;
          k = 0x6ed9eba1;
        } else if (i < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8f1bbcdc;
        } else {
          f = b ^ c ^ d;
          k = 0xca62c1d6;
        }

        const next = (Sha1.#rotateLeft(a, 5) + f + e + k + words[i]) >>> 0;

        e = d;
        d = c;
        c = Sha1.#rotateLeft(b, 30);
        b = a;
        a = next;
      }

      h0 = (h0 + a) >>> 0;
      h1 = (h1 + b) >>> 0;
      h2 = (h2 + c) >>> 0;
      h3 = (h3 + d) >>> 0;
      h4 = (h4 + e) >>> 0;
    }

    const digest = new Uint8Array(20);
    const digestView = new DataView(digest.buffer);

    digestView.setUint32(0, h0, false);
    digestView.setUint32(4, h1, false);
    digestView.setUint32(8, h2, false);
    digestView.setUint32(12, h3, false);
    digestView.setUint32(16, h4, false);

    return digest;
  }

  static #rotateLeft(value, bits) {
    return ((value << bits) | (value >>> (32 - bits))) >>> 0;
  }
}
