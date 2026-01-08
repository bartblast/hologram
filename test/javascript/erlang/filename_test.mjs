"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
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
      const filename = Type.bitstring("path/to/file.txt");
      const result = basename(filename);
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path with single segment", () => {
      const filename = Type.bitstring("file.txt");
      const result = basename(filename);
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path with absolute path", () => {
      const filename = Type.bitstring("/absolute/path/to/file.txt");
      const result = basename(filename);
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path ending with slash", () => {
      const filename = Type.bitstring("path/to/dir/");
      const result = basename(filename);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("root path", () => {
      const filename = Type.bitstring("/");
      const result = basename(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("empty string", () => {
      const emptyString = Type.bitstring("");
      const result = basename(emptyString);

      assert.deepStrictEqual(result, emptyString);
    });

    it("path with multiple consecutive slashes", () => {
      const filename = Type.bitstring("path//to//file.txt");
      const result = basename(filename);
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("path with only slashes", () => {
      const filename = Type.bitstring("///");
      const result = basename(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("bitstring input", () => {
      // "path/to/file.txt"
      const filename = Bitstring.fromBytes([
        112, 97, 116, 104, 47, 116, 111, 47, 102, 105, 108, 101, 46, 116, 120,
        116,
      ]);

      const result = basename(filename);
      const expected = Type.bitstring("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("atom input", () => {
      const filename = Type.atom("path/to/file.txt");
      const result = basename(filename);
      const expected = Type.charlist("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("empty list input", () => {
      const emptyList = Type.list();
      const result = basename(emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("non-empty iolist input", () => {
      const filename = Type.list([
        Type.bitstring("path/to/"),
        Type.integer(102), // 'f'
        Type.integer(105), // 'i'
        Type.integer(108), // 'l'
        Type.integer(101), // 'e'
        Type.bitstring(".txt"),
      ]);

      const result = basename(filename);
      const expected = Type.charlist("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a bitstring or atom or list", () => {
      const arg = Type.integer(123);

      assertBoxedError(
        () => basename(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the argument is a non-binary bitstring", () => {
      const arg = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => basename(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg,
          Type.list(),
        ]),
      );
    });
  });

  describe("flatten/1", () => {
    const flatten = Erlang_Filename["flatten/1"];

    it("binary input returns binary unchanged", () => {
      const filename = Type.bitstring("path/to/file.txt");
      const result = flatten(filename);

      assert.deepStrictEqual(result, filename);
    });

    it("atom input converts to charlist", () => {
      const filename = Type.atom("myfile");
      const result = flatten(filename);
      const expected = Type.charlist("myfile");

      assert.deepStrictEqual(result, expected);
    });

    it("flat list of integers returns as-is", () => {
      const filename = Type.list([
        Type.integer(112), // p
        Type.integer(97), // a
        Type.integer(116), // t
        Type.integer(104), // h
      ]);
      const result = flatten(filename);

      assert.deepStrictEqual(result, filename);
    });

    it("flat list with bitstring elements", () => {
      const filename = Type.list([
        Type.bitstring("foo"),
        Type.bitstring("bar"),
      ]);
      const result = flatten(filename);
      const expected = Type.list([
        Type.bitstring("foo"),
        Type.bitstring("bar"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("nested list with integers flattens correctly", () => {
      const filename = Type.list([
        Type.integer(112), // p
        Type.list([Type.integer(97), Type.integer(116)]), // at
        Type.integer(104), // h
      ]);
      const result = flatten(filename);
      const expected = Type.list([
        Type.integer(112),
        Type.integer(97),
        Type.integer(116),
        Type.integer(104),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("deeply nested list flattens correctly", () => {
      const filename = Type.list([
        Type.list([
          Type.list([Type.integer(97), Type.integer(98)]),
          Type.integer(99),
        ]),
        Type.integer(100),
      ]);
      const result = flatten(filename);
      const expected = Type.list([
        Type.integer(97),
        Type.integer(98),
        Type.integer(99),
        Type.integer(100),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("list with atom elements converts atoms to charcodes", () => {
      const filename = Type.list([
        Type.atom("foo"),
        Type.integer(47), // /
        Type.atom("bar"),
      ]);
      const result = flatten(filename);
      const expected = Type.list([
        Type.integer(102), // f
        Type.integer(111), // o
        Type.integer(111), // o
        Type.integer(47), // /
        Type.integer(98), // b
        Type.integer(97), // a
        Type.integer(114), // r
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("empty list returns empty list", () => {
      const filename = Type.list([]);
      const result = flatten(filename);

      assert.deepStrictEqual(result, filename);
    });

    it("list with empty nested list", () => {
      const filename = Type.list([
        Type.integer(97),
        Type.list([]),
        Type.integer(98),
      ]);
      const result = flatten(filename);
      const expected = Type.list([Type.integer(97), Type.integer(98)]);

      assert.deepStrictEqual(result, expected);
    });

    it("mixed list with bitstrings, atoms, integers and nested lists", () => {
      const filename = Type.list([
        Type.bitstring("path"),
        Type.list([
          Type.integer(47), // /
          Type.atom("to"),
        ]),
        Type.integer(47), // /
        Type.list([Type.bitstring("file.txt")]),
      ]);
      const result = flatten(filename);
      const expected = Type.list([
        Type.bitstring("path"),
        Type.integer(47),
        Type.integer(116), // t
        Type.integer(111), // o
        Type.integer(47),
        Type.bitstring("file.txt"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a binary, atom, or list", () => {
      const arg = Type.integer(123);

      assertBoxedError(
        () => flatten(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the argument is a non-binary bitstring", () => {
      const arg = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => flatten(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg,
          Type.list(),
        ]),
      );
    });
  });
});
