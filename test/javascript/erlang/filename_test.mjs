"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
  iolist,
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

    it("path with multiple segments", () => {
      const result = basename(Type.bitstring("path/to/file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path with single segment", () => {
      const result = basename(Type.bitstring("file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path with absolute path", () => {
      const result = basename(Type.bitstring("/absolute/path/to/file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path ending with slash", () => {
      const result = basename(Type.bitstring("path/to/dir/"));
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("root path", () => {
      const result = basename(Type.bitstring("/"));
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("empty string", () => {
      const result = basename(Type.bitstring(""));
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("path with multiple consecutive slashes", () => {
      const result = basename(Type.bitstring("path//to//file.txt"));
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path with only slashes", () => {
      const result = basename(Type.bitstring("///"));
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("list of code points for atom input", () => {
      const result = basename(Type.atom("path/to/file.txt"));
      const expected = iolist("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("list of code points for atom input with single segment", () => {
      const result = basename(Type.atom("filename"));
      const expected = iolist("filename");

      assert.deepStrictEqual(result, expected);
    });

    it("list of code points for nil atom input", () => {
      const result = basename(Type.nil());
      const expected = iolist("nil");

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a binary or atom or list", () => {
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

    it("list of code points for non-empty list input", () => {
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
      const expected = iolist("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("list of code points for list input with single segment", () => {
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
      const expected = iolist("filename");

      assert.deepStrictEqual(result, expected);
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
