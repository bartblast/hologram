"use strict";

import Bitstring from "./bitstring.mjs";
import Interpreter from "./interpreter.mjs";

// A fixed set of literal terms that answers membership the way strict equality would, one literal
// at a time. Atoms, integers and floats are looked up by their value and binaries by their text,
// so a lookup takes the same time whatever the size of the set. Terms of any other type are
// compared one by one.
//
// The literals come from the given function, which runs once, on the first lookup.
export default class LiteralSet {
  #atoms = new Set();
  #build;
  #floats = new Set();
  #integers = new Set();

  // Bitstrings that have no text: bytes that are not valid UTF-8, or a bit count that is not a
  // multiple of 8.
  #nonTextBitstrings = [];

  #others = [];
  #texts = new Set();

  constructor(build) {
    this.#build = build;
  }

  has(term) {
    if (this.#build !== null) {
      this.#populate();
    }

    switch (term.type) {
      case "atom":
        return this.#atoms.has(term.value);

      case "bitstring":
        return this.#hasBitstring(term);

      case "float":
        return this.#floats.has(term.value);

      case "integer":
        return this.#integers.has(term.value);

      default:
        return this.#others.some((literal) =>
          Interpreter.isStrictlyEqual(literal, term),
        );
    }
  }

  // Whether two bitstrings that both hold bytes are made of the same bits.
  static #haveSameBits(bitstring1, bitstring2) {
    if (bitstring1.leftoverBitCount !== bitstring2.leftoverBitCount) {
      return false;
    }

    const bytes1 = bitstring1.bytes;
    const bytes2 = bitstring2.bytes;

    if (bytes1.length !== bytes2.length) {
      return false;
    }

    for (let i = 0; i < bytes1.length; i++) {
      if (bytes1[i] !== bytes2[i]) {
        return false;
      }
    }

    return true;
  }

  // A bitstring that has text can only equal a literal that has the same text. One that has none
  // can only equal a literal that has none either, and those are compared by their bits - never
  // by their text fields, which say the same thing for all of them.
  #hasBitstring(term) {
    const text = $.#textOf(term);

    if (text !== null) {
      return this.#texts.has(text);
    }

    return this.#nonTextBitstrings.some((literal) =>
      $.#haveSameBits(literal, term),
    );
  }

  #populate() {
    for (const literal of this.#build()) {
      switch (literal.type) {
        case "atom":
          this.#atoms.add(literal.value);
          break;

        case "bitstring": {
          const text = $.#textOf(literal);

          if (text !== null) {
            this.#texts.add(text);
          } else {
            this.#nonTextBitstrings.push(literal);
          }

          break;
        }

        case "float":
          this.#floats.add(literal.value);
          break;

        case "integer":
          this.#integers.add(literal.value);
          break;

        default:
          this.#others.push(literal);
      }
    }

    this.#build = null;
  }

  // The text of a binary whose bytes are valid UTF-8, null for any other bitstring. A binary that
  // holds only bytes is decoded once: the text stays on the term.
  static #textOf(bitstring) {
    if (bitstring.leftoverBitCount !== 0) {
      return null;
    }

    Bitstring.maybeSetTextFromBytes(bitstring);

    return bitstring.text === false ? null : bitstring.text;
  }
}

const $ = LiteralSet;
