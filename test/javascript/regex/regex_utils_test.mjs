"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexUtils from "../../../assets/js/regex/regex_utils.mjs";

defineGlobalErlangAndElixirModules();

describe("RegexUtils", () => {
  describe("byteOffsetToUtf16Index()", () => {
    // a: 1 byte / 1 UTF-16 unit, é: 2 bytes / 1 unit, €: 3 bytes / 1 unit, 😀: 4 bytes / 2 units
    const text = "aé€😀";

    it("returns 0 for offset 0", () => {
      assert.equal(RegexUtils.byteOffsetToUtf16Index(text, 0), 0);
    });

    it("converts offset after 1-byte code point", () => {
      assert.equal(RegexUtils.byteOffsetToUtf16Index(text, 1), 1);
    });

    it("converts offset after 2-byte code point", () => {
      assert.equal(RegexUtils.byteOffsetToUtf16Index(text, 3), 2);
    });

    it("converts offset after 3-byte code point", () => {
      assert.equal(RegexUtils.byteOffsetToUtf16Index(text, 6), 3);
    });

    it("converts offset after 4-byte code point", () => {
      assert.equal(RegexUtils.byteOffsetToUtf16Index(text, 10), 5);
    });

    it("clamps offset past the end of text", () => {
      assert.equal(RegexUtils.byteOffsetToUtf16Index(text, 11), 5);
    });

    it("returns 0 for empty text", () => {
      assert.equal(RegexUtils.byteOffsetToUtf16Index("", 3), 0);
    });
  });

  describe("utf16IndexToByteOffset()", () => {
    // a: 1 byte / 1 UTF-16 unit, é: 2 bytes / 1 unit, €: 3 bytes / 1 unit, 😀: 4 bytes / 2 units
    const text = "aé€😀";

    it("returns 0 for index 0", () => {
      assert.equal(RegexUtils.utf16IndexToByteOffset(text, 0), 0);
    });

    it("converts index after 1-byte code point", () => {
      assert.equal(RegexUtils.utf16IndexToByteOffset(text, 1), 1);
    });

    it("converts index after 2-byte code point", () => {
      assert.equal(RegexUtils.utf16IndexToByteOffset(text, 2), 3);
    });

    it("converts index after 3-byte code point", () => {
      assert.equal(RegexUtils.utf16IndexToByteOffset(text, 3), 6);
    });

    it("converts index after 4-byte code point", () => {
      assert.equal(RegexUtils.utf16IndexToByteOffset(text, 5), 10);
    });

    it("returns 0 for empty text", () => {
      assert.equal(RegexUtils.utf16IndexToByteOffset("", 0), 0);
    });
  });
});
