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

    it("binary with invalid UTF-8 bytes", () => {
      // <<0xFF, 0xFE>> is invalid UTF-8
      const filename = Bitstring.fromBytes([
        112, 97, 116, 104, 47, 116, 111, 47, 0xff, 0xfe, 46, 116, 120, 116,
      ]);

      const result = basename(filename);

      // Should preserve raw bytes for the invalid UTF-8
      const expected = Bitstring.fromBytes([0xff, 0xfe, 46, 116, 120, 116]);

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

    it("iolist with invalid UTF-8 bytes", () => {
      // Pure charlist: [112, 97, 116, 104, 47, 116, 111, 47, 0xFF, 0xFE, 46, 116, 120, 116]
      // "path/to/" + [0xFF, 0xFE] + ".txt"
      const filename = Type.list([
        Type.integer(112), // 'p'
        Type.integer(97), // 'a'
        Type.integer(116), // 't'
        Type.integer(104), // 'h'
        Type.integer(47), // '/'
        Type.integer(116), // 't'
        Type.integer(111), // 'o'
        Type.integer(47), // '/'
        Type.integer(0xff),
        Type.integer(0xfe),
        Type.integer(46), // '.'
        Type.integer(116), // 't'
        Type.integer(120), // 'x'
        Type.integer(116), // 't'
      ]);

      const result = basename(filename);

      // Should return raw bytes as integers: [0xFF, 0xFE, ?., ?t, ?x, ?t]
      const expected = Type.list([
        Type.integer(0xff),
        Type.integer(0xfe),
        Type.integer(46), // '.'
        Type.integer(116), // 't'
        Type.integer(120), // 'x'
        Type.integer(116), // 't'
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("charlist with only slashes", () => {
      const filename = Type.list([
        Type.integer(47), // '/'
        Type.integer(47), // '/'
        Type.integer(47), // '/'
      ]);

      const result = basename(filename);
      const expected = Type.list();

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

    it("binary", () => {
      const filename = Type.bitstring("path/to/file.txt");
      const result = flatten(filename);

      assert.deepStrictEqual(result, filename);
    });

    it("atom", () => {
      const filename = Type.atom("myfile");
      const result = flatten(filename);
      const expected = Type.charlist("myfile");

      assert.deepStrictEqual(result, expected);
    });

    it("flat list of integers", () => {
      const filename = Type.list([
        Type.integer(112),
        Type.integer(97),
        Type.integer(116),
        Type.integer(104),
      ]);

      const result = flatten(filename);

      assert.deepStrictEqual(result, filename);
    });

    it("flat list of bitstrings", () => {
      const filename = Type.list([
        Type.bitstring("foo"),
        Type.bitstring("bar"),
      ]);

      const result = flatten(filename);

      assert.deepStrictEqual(result, filename);
    });

    it("flat list of atoms", () => {
      // # ?f = 102, ?o = 111, ?全 = 20840, ?息 = 24687, ?图 = 22270, ?b = 98, ?a = 97, ?r = 114
      const filename = Type.list([
        Type.atom("foo"),
        Type.atom("全息图"),
        Type.atom("bar"),
      ]);

      const result = flatten(filename);

      const expected = Type.list([
        Type.integer(102),
        Type.integer(111),
        Type.integer(111),
        Type.integer(20840),
        Type.integer(24687),
        Type.integer(22270),
        Type.integer(98),
        Type.integer(97),
        Type.integer(114),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("nested list of integers", () => {
      const filename = Type.list([
        Type.integer(112),
        Type.list([Type.integer(97), Type.integer(116)]),
        Type.integer(104),
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

    it("deeply nested list of integers", () => {
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

    it("empty list", () => {
      const filename = Type.list();
      const result = flatten(filename);

      assert.deepStrictEqual(result, filename);
    });

    it("list with an empty list element", () => {
      const filename = Type.list([
        Type.integer(97),
        Type.list(),
        Type.integer(98),
      ]);

      const result = flatten(filename);
      const expected = Type.list([Type.integer(97), Type.integer(98)]);

      assert.deepStrictEqual(result, expected);
    });

    it("mixed list with bitstrings, atoms, integers and nested lists", () => {
      // ?t = 116, ?o = 111
      const filename = Type.list([
        Type.bitstring("path"),
        Type.list([Type.integer(47), Type.atom("to")]),
        Type.integer(63),
        Type.list([Type.bitstring("file.txt")]),
      ]);

      const result = flatten(filename);

      const expected = Type.list([
        Type.bitstring("path"),
        Type.integer(47),
        Type.integer(116),
        Type.integer(111),
        Type.integer(63),
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

  describe("split/1", () => {
    const split = Erlang_Filename["split/1"];

    it("absolute Unix path", () => {
      const filename = Type.bitstring("/usr/local/bin");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("/"),
        Type.bitstring("usr"),
        Type.bitstring("local"),
        Type.bitstring("bin"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("relative Unix path", () => {
      const filename = Type.bitstring("foo/bar");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("foo"),
        Type.bitstring("bar"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("single component", () => {
      const filename = Type.bitstring("foo");
      const result = split(filename);
      const expected = Type.list([Type.bitstring("foo")]);

      assert.deepStrictEqual(result, expected);
    });

    it("root path", () => {
      const filename = Type.bitstring("/");
      const result = split(filename);
      const expected = Type.list([Type.bitstring("/")]);

      assert.deepStrictEqual(result, expected);
    });

    it("empty string", () => {
      const filename = Type.bitstring("");
      const result = split(filename);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple consecutive slashes", () => {
      const filename = Type.bitstring("//");
      const result = split(filename);
      const expected = Type.list([Type.bitstring("/")]);

      assert.deepStrictEqual(result, expected);
    });

    it("dot component", () => {
      const filename = Type.bitstring(".");
      const result = split(filename);
      const expected = Type.list([Type.bitstring(".")]);

      assert.deepStrictEqual(result, expected);
    });

    it("double dot component", () => {
      const filename = Type.bitstring("..");
      const result = split(filename);
      const expected = Type.list([Type.bitstring("..")]);

      assert.deepStrictEqual(result, expected);
    });

    it("path with dot in middle", () => {
      const filename = Type.bitstring("/./");
      const result = split(filename);
      const expected = Type.list([Type.bitstring("/"), Type.bitstring(".")]);

      assert.deepStrictEqual(result, expected);
    });

    it("path with double dot in middle", () => {
      const filename = Type.bitstring("/../");
      const result = split(filename);
      const expected = Type.list([Type.bitstring("/"), Type.bitstring("..")]);

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with dot prefix", () => {
      const filename = Type.bitstring("./foo");
      const result = split(filename);
      const expected = Type.list([Type.bitstring("."), Type.bitstring("foo")]);

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with double dot prefix", () => {
      const filename = Type.bitstring("../foo");
      const result = split(filename);
      const expected = Type.list([Type.bitstring(".."), Type.bitstring("foo")]);

      assert.deepStrictEqual(result, expected);
    });

    it("path with dot in middle components", () => {
      const filename = Type.bitstring("foo/./bar");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("foo"),
        Type.bitstring("."),
        Type.bitstring("bar"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("path with double dot in middle components", () => {
      const filename = Type.bitstring("foo/../bar");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("foo"),
        Type.bitstring(".."),
        Type.bitstring("bar"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("path with trailing slash", () => {
      const filename = Type.bitstring("foo/bar/");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("foo"),
        Type.bitstring("bar"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("absolute path with trailing slash", () => {
      const filename = Type.bitstring("/foo/bar/");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("/"),
        Type.bitstring("foo"),
        Type.bitstring("bar"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("path with multiple consecutive slashes in middle", () => {
      const filename = Type.bitstring("foo//bar");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("foo"),
        Type.bitstring("bar"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("drive letter with colon and forward slash", () => {
      const filename = Type.bitstring("a:/msdev/include");
      const result = split(filename);
      const expected = Type.list([
        Type.bitstring("a:"),
        Type.bitstring("msdev"),
        Type.bitstring("include"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("charlist input", () => {
      const filename = Type.charlist("foo/bar");
      const result = split(filename);
      const expected = Type.list([Type.charlist("foo"), Type.charlist("bar")]);

      assert.deepStrictEqual(result, expected);
    });

    it("charlist input with absolute path", () => {
      const filename = Type.charlist("/usr/local/bin");
      const result = split(filename);
      const expected = Type.list([
        Type.charlist("/"),
        Type.charlist("usr"),
        Type.charlist("local"),
        Type.charlist("bin"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("atom input", () => {
      const filename = Type.atom("foo/bar");
      const result = split(filename);
      const expected = Type.list([Type.charlist("foo"), Type.charlist("bar")]);

      assert.deepStrictEqual(result, expected);
    });

    it("empty list input", () => {
      const filename = Type.list([]);
      const result = split(filename);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("iolist input", () => {
      const filename = Type.list([
        Type.bitstring("foo"),
        Type.integer(47), // '/'
        Type.bitstring("bar"),
      ]);
      const result = split(filename);
      const expected = Type.list([Type.charlist("foo"), Type.charlist("bar")]);

      assert.deepStrictEqual(result, expected);
    });

    it("binary with invalid UTF-8 bytes", () => {
      // "usr/" + <<0xFF, 0xFE>> (invalid UTF-8) + "/bin"
      const filename = Bitstring.fromBytes([
        117, 115, 114, 47, 0xff, 0xfe, 47, 98, 105, 110,
      ]);

      const result = split(filename);
      // Should preserve raw bytes: ["usr", <<0xFF, 0xFE>>, "bin"]
      const invalidUtf8Part = Bitstring.fromBytes([0xff, 0xfe]);
      Bitstring.maybeSetTextFromBytes(invalidUtf8Part);
      const expected = Type.list([
        Type.bitstring("usr"),
        invalidUtf8Part,
        Type.bitstring("bin"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("iolist with invalid UTF-8 bytes", () => {
      // Pure charlist: [117, 115, 114, 47, 0xFF, 0xFE, 47, 98, 105, 110]
      // "usr/" + [0xFF, 0xFE] + "/bin"
      const filename = Type.list([
        Type.integer(117), // 'u'
        Type.integer(115), // 's'
        Type.integer(114), // 'r'
        Type.integer(47), // '/'
        Type.integer(0xff),
        Type.integer(0xfe),
        Type.integer(47), // '/'
        Type.integer(98), // 'b'
        Type.integer(105), // 'i'
        Type.integer(110), // 'n'
      ]);

      const result = split(filename);
      // Should return raw bytes as integers: [[117, 115, 114], [0xFF, 0xFE], [98, 105, 110]]
      const expected = Type.list([
        Type.charlist("usr"),
        Type.list([Type.integer(0xff), Type.integer(0xfe)]),
        Type.charlist("bin"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a valid filename type", () => {
      const arg = Type.integer(123);

      assertBoxedError(
        () => split(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg,
          Type.list([]),
        ]),
      );
    });
  });
});
