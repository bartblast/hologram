"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Filelib from "../../../assets/js/erlang/filelib.mjs";
import Type from "../../../assets/js/type.mjs";
import Bitstring from "../../../assets/js/bitstring.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/filelib_test.exs
// Always update both together.

describe("Erlang_Filelib", () => {
  describe("safe_relative_path/2", () => {
    const safeRelativePath = Erlang_Filelib["safe_relative_path/2"];

    it("relative path with single component", () => {
      const filename = Type.bitstring("dir");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with multiple components", () => {
      const filename = Type.bitstring("dir/sub_dir");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir/sub_dir");

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with .. that stays within bounds", () => {
      const filename = Type.bitstring("dir/sub_dir/..");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with .. that returns to root", () => {
      const filename = Type.bitstring("dir/..");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with .. that escapes root", () => {
      const filename = Type.bitstring("dir/../..");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.atom("unsafe");

      assert.deepStrictEqual(result, expected);
    });

    it("absolute path", () => {
      const filename = Type.bitstring("/abs/path");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.atom("unsafe");

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with . components", () => {
      const filename = Type.bitstring("./dir/./sub");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir/sub");

      assert.deepStrictEqual(result, expected);
    });

    it("empty path", () => {
      const filename = Type.bitstring("");
      const cwd = Type.bitstring("/home/user");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("charlist relative path", () => {
      // "dir"
      const filename = Type.list([
        Type.integer(100),
        Type.integer(105),
        Type.integer(114),
      ]);
      const cwd = Type.list([Type.integer(47)]);
      const result = safeRelativePath(filename, cwd);
      // "dir"
      const expected = Type.list([
        Type.integer(100),
        Type.integer(105),
        Type.integer(114),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("charlist path with ..", () => {
      // "dir/.."
      const filename = Type.list([
        Type.integer(100),
        Type.integer(105),
        Type.integer(114),
        Type.integer(47),
        Type.integer(46),
        Type.integer(46),
      ]);
      const cwd = Type.list([Type.integer(47)]);
      const result = safeRelativePath(filename, cwd);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("charlist path escaping root", () => {
      // "dir/../.."
      const filename = Type.list([
        Type.integer(100),
        Type.integer(105),
        Type.integer(114),
        Type.integer(47),
        Type.integer(46),
        Type.integer(46),
        Type.integer(47),
        Type.integer(46),
        Type.integer(46),
      ]);
      const cwd = Type.list([Type.integer(47)]);
      const result = safeRelativePath(filename, cwd);
      const expected = Type.atom("unsafe");

      assert.deepStrictEqual(result, expected);
    });

    it("cwd with empty string is normalized to dot", () => {
      const filename = Type.bitstring("dir");
      const cwd = Type.bitstring("");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("cwd with empty list is normalized to dot", () => {
      const filename = Type.bitstring("dir");
      const cwd = Type.list([]);
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("path with multiple consecutive .. components", () => {
      const filename = Type.bitstring("a/b/c/../../..");
      const cwd = Type.bitstring("/home");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("path with multiple consecutive .. that escapes", () => {
      const filename = Type.bitstring("a/b/../../../../");
      const cwd = Type.bitstring("/home");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.atom("unsafe");

      assert.deepStrictEqual(result, expected);
    });

    it("path with trailing slashes", () => {
      const filename = Type.bitstring("dir/sub/");
      const cwd = Type.bitstring("/home");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir/sub");

      assert.deepStrictEqual(result, expected);
    });

    it("path with only . components", () => {
      const filename = Type.bitstring("./.././.");
      const cwd = Type.bitstring("/home");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.atom("unsafe");

      assert.deepStrictEqual(result, expected);
    });

    it("binary input", () => {
      const filename = Type.bitstring("dir");
      const cwd = Type.bitstring("/home");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("mixed binary and charlist", () => {
      const filename = Type.bitstring("dir");
      const cwd = Type.list([
        Type.integer(47), // "/"
        Type.integer(104), // "h"
        Type.integer(111), // "o"
        Type.integer(109), // "m"
        Type.integer(101), // "e"
      ]);
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });

    it("invalid utf-8 bytes", () => {
      const invalidUtf8 = Bitstring.fromBytes([0xff, 0xfe]);
      const cwd = Type.bitstring("/home");
      const result = safeRelativePath(invalidUtf8, cwd);

      // Erlang returns invalid UTF-8 bytes as-is
      assert.strictEqual(result.bytes[0], 0xff);
      assert.strictEqual(result.bytes[1], 0xfe);
      assert.strictEqual(result.bytes.length, 2);
    });

    it("cwd with invalid type", () => {
      const filename = Type.bitstring("dir");
      const cwd = Type.integer(123);

      assertBoxedError(
        () => safeRelativePath(filename, cwd),
        "FunctionClauseError",
        /safe_relative_path\/2/,
      );
    });

    it("cwd with valid atom type", () => {
      const filename = Type.bitstring("dir");
      const cwd = Type.atom("ok");
      const result = safeRelativePath(filename, cwd);
      const expected = Type.bitstring("dir");

      assert.deepStrictEqual(result, expected);
    });
  });
});
