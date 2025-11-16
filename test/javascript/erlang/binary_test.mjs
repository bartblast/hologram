"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Erlang_Binary", () => {
  describe("at/2", () => {
    const at = Erlang_Binary["at/2"];

    it("returns byte at position 0", () => {
      const binary = Type.bitstring([
        0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 0, 0,
        0, 0, 1, 0, 0, 0, 0, 1,
      ]); // <<5, 19, 72, 33>>
      const result = at(binary, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns byte at position 1", () => {
      const binary = Type.bitstring([
        0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 0, 0,
        0, 0, 1, 0, 0, 0, 0, 1,
      ]); // <<5, 19, 72, 33>>
      const result = at(binary, Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(19));
    });

    it("raises ArgumentError when position is out of range", () => {
      const binary = Type.bitstring([
        0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 0, 0,
        0, 0, 1, 0, 0, 0, 0, 1,
      ]); // <<5, 19, 72, 33>>
      const pos = Type.integer(4);

      assertBoxedError(
        () => at(binary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("single element binary from text", () => {
      const result = at(Type.bitstring("a"), Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(97));
    });

    it("multi-byte binary from text, first position", () => {
      const subject = Type.bitstring("hello");
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(104)); // 'h)'
    });

    it("multi-byte binary from text, middle position", () => {
      const subject = Type.bitstring("hello");
      const result = at(subject, Type.integer(2));

      assert.deepStrictEqual(result, Type.integer(108)); // 'l)'
    });

    it("multi-byte binary from text, last position", () => {
      const subject = Type.bitstring("hello");
      const result = at(subject, Type.integer(4));

      assert.deepStrictEqual(result, Type.integer(111)); // 'o)'
    });

    it("longer text binary", () => {
      const subject = Type.bitstring(
        "The quick brown fox jumps over the lazy dog",
      );
      const result = at(subject, Type.integer(16));

      assert.deepStrictEqual(result, Type.integer(102)); // 'f)'
    });

    it("very long text binary", () => {
      const longText =
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " +
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " +
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris " +
        "nisi ut aliquip ex ea commodo consequat.";
      const subject = Type.bitstring(longText);
      const result = at(subject, Type.integer(100));

      assert.deepStrictEqual(result, Type.integer(101)); // 'e)'
    });

    it("binary with Unicode emoji at ASCII position", () => {
      const subject = Type.bitstring("Hello 😀 World");
      // Position 6 is the first byte of the emoji (UTF-8 encoded)
      const result = at(subject, Type.integer(6));

      assert.deepStrictEqual(result, Type.integer(0xf0)); // First byte of 😀 in UTF-)8
    });

    it("binary with Unicode emoji, position after emoji", () => {
      const subject = Type.bitstring("Hi😀!");
      // The emoji takes 4 bytes in UTF-8, so '!' is at position 6
      const result = at(subject, Type.integer(6));

      assert.deepStrictEqual(result, Type.integer(33)); // '!)'
    });

    it("binary with multiple Unicode characters", () => {
      const subject = Type.bitstring("🎉🎊🎈");
      // First byte of the second emoji (🎊)
      const result = at(subject, Type.integer(4));

      assert.deepStrictEqual(result, Type.integer(0xf0)); // First byte of 🎊 in UTF-)8
    });

    it("binary with mixed ASCII and Unicode", () => {
      const subject = Type.bitstring("Test 测试 🔬");
      // Position 5 should be the first byte of the Chinese character '测'
      const result = at(subject, Type.integer(5));

      assert.deepStrictEqual(result, Type.integer(0xe6)); // First byte of '测' in UTF-)8
    });

    it("binary with various Unicode symbols", () => {
      const subject = Type.bitstring("♠♣♥♦");
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(0xe2)); // First byte of '♠' in UTF-)8
    });

    it("binary with Unicode combining characters", () => {
      const subject = Type.bitstring("Café"); // é = e + combining acute accent
      const result = at(subject, Type.integer(3));

      assert.deepStrictEqual(result, Type.integer(0xc3)); // First byte of 'é' in UTF-)8
    });

    it("binary from bits, valid byte boundary", () => {
      const subject = Type.bitstring([0, 1, 0, 0, 0, 0, 0, 1]); // 65 = 'A'
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(65));
    });

    it("binary from multiple bytes in bits", () => {
      const subject = Type.bitstring([
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1, // 65 = 'A'
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0, // 66 = 'B'
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        1, // 67 = 'C'
      ]);
      const result = at(subject, Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(66)); // 'B)'
    });

    it("first arg is a bitstring from bits, but not a binary", () => {
      const subject = Type.bitstring([1, 0, 1]);
      const pos = Type.integer(0);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("second arg is a negative integer", () => {
      const subject = Type.bitstring("a");
      const pos = Type.integer(-1);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("second arg exceeds bounds", () => {
      const subject = Type.bitstring("a");
      const pos = Type.integer(2);

      assertBoxedError(
        () => at(subject, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("second arg at exact boundary (one past last index)", () => {
      const subject = Type.bitstring("test");
      const pos = Type.integer(4);

      assertBoxedError(
        () => at(subject, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("second arg far exceeds bounds", () => {
      const subject = Type.bitstring("hi");
      const pos = Type.integer(1000);

      assertBoxedError(
        () => at(subject, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("empty binary from text", () => {
      const subject = Type.bitstring("");
      const pos = Type.integer(0);

      assertBoxedError(
        () => at(subject, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("empty binary from bits", () => {
      const subject = Type.bitstring([]);
      const pos = Type.integer(0);

      assertBoxedError(
        () => at(subject, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("position is zero for valid binary", () => {
      const subject = Type.bitstring("xyz");
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(120)); // 'x)'
    });

    it("binary with null byte", () => {
      const subject = Type.bitstring([0, 0, 0, 0, 0, 0, 0, 0]); // null byte
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("binary with all bits set", () => {
      const subject = Type.bitstring([1, 1, 1, 1, 1, 1, 1, 1]); // 255
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(255));
    });

    it("binary with mixed null and non-null bytes", () => {
      const subject = Type.bitstring([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0, // null byte
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1, // 65 = 'A'
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0, // null byte
      ]);
      const result = at(subject, Type.integer(2));

      assert.deepStrictEqual(result, Type.integer(0)); // third byte is nul)l
    });

    it("first arg is not a bitstring (integer)", () => {
      const subject = Type.integer(123);
      const pos = Type.integer(0);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("first arg is not a bitstring (atom)", () => {
      const subject = Type.atom("test");
      const pos = Type.integer(0);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("first arg is not a bitstring (list)", () => {
      const subject = Type.list([Type.integer(1), Type.integer(2)]);
      const pos = Type.integer(0);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("second arg is not an integer (atom)", () => {
      const subject = Type.bitstring("test");
      const pos = Type.atom("zero");

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("second arg is not an integer (float)", () => {
      const subject = Type.bitstring("test");
      const pos = Type.float(0.0);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("second arg is zero (edge case for valid position)", () => {
      const subject = Type.bitstring("a");
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(97)); // 'a)'
    });

    it("binary with only whitespace", () => {
      const subject = Type.bitstring("   ");
      const result = at(subject, Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(32)); // space characte)r
    });

    it("binary with newline and tab characters", () => {
      const subject = Type.bitstring("a\n\tb");
      const result = at(subject, Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(10)); // newline characte)r
    });

    it("binary with special characters", () => {
      const subject = Type.bitstring("!@#$%^&*()");
      const result = at(subject, Type.integer(5));

      assert.deepStrictEqual(result, Type.integer(94)); // '^)'
    });

    it("single byte binary from bits with maximum value", () => {
      const subject = Type.bitstring([1, 1, 1, 1, 1, 1, 1, 1]); // 255
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(255));
    });

    it("single byte binary from bits with minimum value", () => {
      const subject = Type.bitstring([0, 0, 0, 0, 0, 0, 0, 0]); // 0
      const result = at(subject, Type.integer(0));

      assert.deepStrictEqual(result, Type.integer(0));
    });
  });
});
