"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Filename from "../../../assets/js/erlang/filename.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/filename_test.exs
// Always update both together.

describe("Erlang_Filename", () => {
  describe("basename/1", () => {
    const basename = Erlang_Filename["basename/1"];

    it("returns basename for path with multiple segments", () => {
      const result = basename(Type.bitstring("path/to/file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path with single segment", () => {
      const result = basename(Type.bitstring("file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path with absolute path", () => {
      const result = basename(Type.bitstring("/absolute/path/to/file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path ending with slash", () => {
      const result = basename(Type.bitstring("path/to/dir/"));
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for root path", () => {
      const result = basename(Type.bitstring("/"));
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for empty string", () => {
      const result = basename(Type.bitstring(""));
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path with multiple consecutive slashes", () => {
      const result = basename(Type.bitstring("path//to//file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path with only slashes", () => {
      const result = basename(Type.bitstring("///"));
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path without extension", () => {
      const result = basename(Type.bitstring("path/to/filename"));
      const expected = Type.bitstring("filename");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path with unicode characters", () => {
      const result = basename(Type.bitstring("path/to/文件.txt"));
      const expected = Type.bitstring("文件.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename for path with special characters", () => {
      const result = basename(Type.bitstring("path/to/file-name_123.txt"));
      const expected = Type.bitstring("file-name_123.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename as list of code points for atom input", () => {
      const result = basename(Type.atom("path/to/file.txt"));
      const expected = Type.list(
        Array.from("file.txt", (char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename as list of code points for atom input with single segment", () => {
      const result = basename(Type.atom("filename"));
      const expected = Type.list(
        Array.from("filename", (char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename as list of code points for nil atom input", () => {
      const result = basename(Type.nil());
      const expected = Type.list(
        Array.from("nil", (char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename as list of code points for nil atom input with path", () => {
      const result = basename(Type.atom("path/to/nil"));
      const expected = Type.list(
        Array.from("nil", (char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename as list of code points for atom input with unicode characters", () => {
      const result = basename(Type.atom("path/to/文件.txt"));
      const expected = Type.list(
        Array.from("文件.txt", (char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a binary or atom", () => {
      assertBoxedError(
        () => basename(Type.integer(123)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          Type.integer(123),
          Type.list([]),
        ]),
      );
    });

    it("returns empty list for empty list input", () => {
      const result = basename(Type.list([]));
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename as list of code points for non-empty list input", () => {
      const result = basename(
        Type.list([
          Type.bitstring("path/to/"),
          Type.integer(102), // 'f'
          Type.integer(105), // 'i'
          Type.integer(108), // 'l'
          Type.integer(101), // 'e'
          Type.bitstring(".txt"),
        ]),
      );
      const expected = Type.list(
        Array.from("file.txt", (char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("returns basename as list of code points for list input with single segment", () => {
      const result = basename(
        Type.list([
          Type.integer(102), // 'f'
          Type.integer(105), // 'i'
          Type.integer(108), // 'l'
          Type.integer(101), // 'e'
          Type.integer(110), // 'n'
          Type.integer(97), // 'a'
          Type.integer(109), // 'm'
          Type.integer(101), // 'e'
        ]),
      );
      const expected = Type.list(
        Array.from("filename", (char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is a tuple", () => {
      const tuple = Type.tuple([Type.integer(1), Type.integer(2)]);
      assertBoxedError(
        () => basename(tuple),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          tuple,
          Type.list([]),
        ]),
      );
    });

    it("raises FunctionClauseError if the argument is a non-binary bitstring", () => {
      const nonBinaryBitstring = Type.bitstring([1, 0, 1]);
      assertBoxedError(
        () => basename(nonBinaryBitstring),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          nonBinaryBitstring,
          Type.list([]),
        ]),
      );
    });
  });
});

