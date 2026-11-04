"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import StringOrder from "../../assets/js/string_order.mjs";

defineRuntimeGlobals();

describe("StringOrder", () => {
  describe("compare()", () => {
    it("compares equal strings as equal", () => {
      assert.equal(StringOrder.compare("zebra", "zebra"), 0);
    });

    it("compares by the first character that differs", () => {
      assert.equal(StringOrder.compare("apple", "apricot"), -1);
      assert.equal(StringOrder.compare("apricot", "apple"), 1);
    });

    it("puts a string before a longer one it starts", () => {
      assert.equal(StringOrder.compare("app", "apple"), -1);
      assert.equal(StringOrder.compare("apple", "app"), 1);
    });

    // In UTF-16 a character above U+FFFF is two code units from 0xD800-0xDFFF, which sort below the
    // code units 0xE000-0xFFFF - while the character sorts above them.
    it("puts a character above U+FFFF after one from U+E000 to U+FFFF", () => {
      assert.equal(StringOrder.compare("\uFFFD", "😀"), -1);
      assert.equal(StringOrder.compare("😀", "\uFFFD"), 1);
      assert.equal(StringOrder.compare("\uE000", "😀"), -1);
    });

    it("compares two characters above U+FFFF by code point", () => {
      assert.equal(StringOrder.compare("😀", "😁"), -1);
      assert.equal(StringOrder.compare("𝔸", "😀"), -1);
    });

    it("compares two characters from U+E000 to U+FFFF by code point", () => {
      assert.equal(StringOrder.compare("\uE000", "\uFFFD"), -1);
    });

    it("puts a character below U+D800 before one above U+FFFF", () => {
      assert.equal(StringOrder.compare("é", "😀"), -1);
      assert.equal(StringOrder.compare("\uD7FF", "😀"), -1);
    });
  });
});
