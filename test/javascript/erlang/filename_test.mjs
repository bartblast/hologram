"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
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

  describe("basename/2", () => {
    const basename = Erlang_Filename["basename/2"];

    it("removes matching extension from simple filename", () => {
      const filename = Type.bitstring("file.txt");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("removes matching extension from path", () => {
      const filename = Type.bitstring("/path/to/file.txt");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("removes multi-part extension", () => {
      const filename = Type.bitstring("file.tar.gz");
      const ext = Type.bitstring(".tar.gz");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("removes partial extension when multiple exist", () => {
      const filename = Type.bitstring("file.tar.gz");
      const ext = Type.bitstring(".gz");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file.tar");

      assertBoxedStrictEqual(result, expected);
    });

    it("returns basename when extension does not match", () => {
      const filename = Type.bitstring("noextension");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("noextension");

      assertBoxedStrictEqual(result, expected);
    });

    it("returns basename when extension partially matches", () => {
      const filename = Type.bitstring("file.txt");
      const ext = Type.bitstring("x");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file.txt");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles root path", () => {
      const filename = Type.bitstring("/");
      const ext = Type.bitstring("x");
      const result = basename(filename, ext);
      const expected = Type.bitstring("");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles empty filename", () => {
      const filename = Type.bitstring("");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("");

      assertBoxedStrictEqual(result, expected);
    });

    it("removes extension from double-dotted filename", () => {
      const filename = Type.bitstring("file.txt.txt");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file.txt");

      assertBoxedStrictEqual(result, expected);
    });

    it("removes extension that equals the entire basename", () => {
      const filename = Type.bitstring(".hidden");
      const ext = Type.bitstring(".hidden");
      const result = basename(filename, ext);
      const expected = Type.bitstring("");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles charlist filename and extension", () => {
      const filename = Type.charlist("file.txt");
      const ext = Type.charlist(".txt");
      const result = basename(filename, ext);
      const expected = Type.charlist("file");

      assert.deepStrictEqual(result, expected);
    });

    it("handles charlist with path", () => {
      const filename = Type.charlist("path/to/file.erl");
      const ext = Type.charlist(".erl");
      const result = basename(filename, ext);
      const expected = Type.charlist("file");

      assert.deepStrictEqual(result, expected);
    });

    it("handles atom filename and extension", () => {
      const filename = Type.atom("file.txt");
      const ext = Type.atom(".txt");
      const result = basename(filename, ext);
      const expected = Type.charlist("file");

      assert.deepStrictEqual(result, expected);
    });

    it("returns empty list for root with charlist", () => {
      const filename = Type.charlist("/");
      const ext = Type.charlist("x");
      const result = basename(filename, ext);
      const expected = Type.list();

      assert.deepStrictEqual(result, expected);
    });

    it("handles iolist filename", () => {
      const filename = Type.list([
        Type.charlist("path/to/"),
        Type.integer(102), // 'f'
        Type.integer(105), // 'i'
        Type.integer(108), // 'l'
        Type.integer(101), // 'e'
        Type.charlist(".txt"),
      ]);

      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("returns basename when extension is longer than basename", () => {
      const filename = Type.bitstring("a.b");
      const ext = Type.bitstring(".longer");
      const result = basename(filename, ext);
      const expected = Type.bitstring("a.b");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles extension with no dot", () => {
      const filename = Type.bitstring("file.txt");
      const ext = Type.bitstring("txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file.");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles empty extension - returns full basename", () => {
      const filename = Type.bitstring("file.txt");
      const ext = Type.bitstring("");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file.txt");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles path with trailing slash", () => {
      const filename = Type.bitstring("path/to/dir/");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("dir");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles multiple consecutive slashes", () => {
      const filename = Type.bitstring("path//to//file.txt");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles only slashes", () => {
      const filename = Type.bitstring("///");
      const ext = Type.bitstring("x");
      const result = basename(filename, ext);
      const expected = Type.bitstring("");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles hidden file with extension", () => {
      const filename = Type.bitstring(".hidden.txt");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring(".hidden");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles file with only dot as name", () => {
      const filename = Type.bitstring(".");
      const ext = Type.bitstring(".");
      const result = basename(filename, ext);
      const expected = Type.bitstring("");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles file with double dots", () => {
      const filename = Type.bitstring("..");
      const ext = Type.bitstring(".");
      const result = basename(filename, ext);
      const expected = Type.bitstring(".");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles long extension", () => {
      const filename = Type.bitstring("archive.tar.gz.bak");
      const ext = Type.bitstring(".tar.gz.bak");
      const result = basename(filename, ext);
      const expected = Type.bitstring("archive");

      assertBoxedStrictEqual(result, expected);
    });

    it("matches binary/charlist mismatch - binary filename, charlist ext", () => {
      const filename = Type.bitstring("file.erl");
      const ext = Type.charlist(".erl");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("matches charlist filename, binary ext", () => {
      const filename = Type.charlist("file.erl");
      const ext = Type.bitstring(".erl");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("returns basename when extension equals basename", () => {
      const filename = Type.bitstring("file");
      const ext = Type.bitstring("file");
      const result = basename(filename, ext);
      const expected = Type.bitstring("");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles iolist with mixed types", () => {
      const filename = Type.list([
        Type.charlist("path/to/"),
        Type.integer(102), // 'f'
        Type.integer(105), // 'i'
        Type.integer(108), // 'l'
        Type.integer(101), // 'e'
        Type.charlist(".erl"),
      ]);

      const ext = Type.charlist(".erl");
      const result = basename(filename, ext);
      const expected = Type.charlist("file");

      assert.deepStrictEqual(result, expected);
    });

    it("handles case-sensitive extension matching", () => {
      const filename = Type.bitstring("file.TXT");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file.TXT");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles multi-byte UTF-8 characters in filename", () => {
      const filename = Type.bitstring("文件.txt");
      const ext = Type.bitstring(".txt");
      const result = basename(filename, ext);
      const expected = Type.bitstring("文件");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles multi-byte UTF-8 characters in extension", () => {
      const filename = Type.bitstring("file.日本");
      const ext = Type.bitstring(".日本");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file");

      assertBoxedStrictEqual(result, expected);
    });

    it("handles path with dot in directory name but not matching extension", () => {
      const filename = Type.bitstring("path.dir/file.txt");
      const ext = Type.bitstring(".dir");
      const result = basename(filename, ext);
      const expected = Type.bitstring("file.txt");

      assertBoxedStrictEqual(result, expected);
    });

    it("returns charlist when basename/1 returns charlist and no match", () => {
      const filename = Type.charlist("path/to/noextension");
      const ext = Type.charlist(".txt");
      const result = basename(filename, ext);
      const expectedBasename = Erlang_Filename["basename/1"](filename);

      assert.deepStrictEqual(result, expectedBasename);
    });

    it("handles empty charlist extension", () => {
      const filename = Type.charlist("file.txt");
      const ext = Type.charlist("");
      const result = basename(filename, ext);
      const expected = Type.charlist("file.txt");

      assert.deepStrictEqual(result, expected);
    });

    it("empty list input", () => {
      const filename = Type.list();
      const ext = Type.charlist(".txt");
      const result = basename(filename, ext);
      const expected = Type.list();

      assert.deepStrictEqual(result, expected);
    });

    it("binary with invalid UTF-8 bytes", () => {
      // <<0xFF, 0xFE, ".txt">>
      const filename = Bitstring.fromBytes([0xff, 0xfe, 46, 116, 120, 116]);

      const ext = Type.bitstring(".txt");

      const result = basename(filename, ext);
      const expected = Bitstring.fromBytes([0xff, 0xfe]);

      assertBoxedStrictEqual(result, expected);
    });

    it("iolist with invalid UTF-8 bytes", () => {
      // [0xFF, 0xFE, ?., ?t, ?x, ?t] - charlist with invalid UTF-8
      const filename = Type.list([
        Type.integer(0xff),
        Type.integer(0xfe),
        Type.integer(46), // '.'
        Type.integer(116), // 't'
        Type.integer(120), // 'x'
        Type.integer(116), // 't'
      ]);

      const ext = Type.charlist(".txt");
      const result = basename(filename, ext);

      const expected = Type.list([Type.integer(0xff), Type.integer(0xfe)]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if filename is invalid", () => {
      const filename = Type.integer(123);
      const ext = Type.bitstring(".txt");

      assertBoxedError(
        () => basename(filename, ext),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          filename,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if extension is invalid", () => {
      const filename = Type.bitstring("file.txt");
      const ext = Type.integer(123);

      assertBoxedError(
        () => basename(filename, ext),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          ext,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if filename is a non-binary bitstring", () => {
      const filename = Type.bitstring([1, 0, 1]);
      const ext = Type.bitstring(".txt");

      assertBoxedError(
        () => basename(filename, ext),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          filename,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if extension is a non-binary bitstring", () => {
      const filename = Type.bitstring("file.txt");
      const ext = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => basename(filename, ext),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          ext,
          Type.list(),
        ]),
      );
    });
  });

  describe("dirname/1", () => {
    const dirname = Erlang_Filename["dirname/1"];

    it("relative path with multiple components", () => {
      const filename = Type.bitstring("foo/bar/baz.erl");
      const result = dirname(filename);
      const expected = Type.bitstring("foo/bar");

      assert.deepStrictEqual(result, expected);
    });

    it("absolute path with multiple components", () => {
      const filename = Type.bitstring("/foo/bar");
      const result = dirname(filename);
      const expected = Type.bitstring("/foo");

      assert.deepStrictEqual(result, expected);
    });

    it("single filename without path", () => {
      const filename = Type.bitstring("foo");
      const result = dirname(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("root path", () => {
      const filename = Type.bitstring("/");
      const result = dirname(filename);
      const expected = Type.bitstring("/");

      assert.deepStrictEqual(result, expected);
    });

    it("absolute path with one component", () => {
      const filename = Type.bitstring("/foo");
      const result = dirname(filename);
      const expected = Type.bitstring("/");

      assert.deepStrictEqual(result, expected);
    });

    it("absolute path with trailing slash", () => {
      const filename = Type.bitstring("/foo/");
      const result = dirname(filename);
      const expected = Type.bitstring("/foo");

      assert.deepStrictEqual(result, expected);
    });

    it("relative path with trailing slash", () => {
      const filename = Type.bitstring("foo/");
      const result = dirname(filename);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("multi-component path with trailing slash", () => {
      const filename = Type.bitstring("foo/bar/baz/");
      const result = dirname(filename);
      const expected = Type.bitstring("foo/bar/baz");

      assert.deepStrictEqual(result, expected);
    });

    it("multi-component path with multiple trailing slashes", () => {
      const filename = Type.bitstring("foo/bar//");
      const result = dirname(filename);
      const expected = Type.bitstring("foo/bar");

      assert.deepStrictEqual(result, expected);
    });

    it("single dot", () => {
      const filename = Type.bitstring(".");
      const result = dirname(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("double dots", () => {
      const filename = Type.bitstring("..");
      const result = dirname(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("consecutive slashes in middle of path", () => {
      const filename = Type.bitstring("foo//bar");
      const result = dirname(filename);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("empty string", () => {
      const filename = Type.bitstring("");
      const result = dirname(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("filename with extension only", () => {
      const filename = Type.bitstring("foo.txt");
      const result = dirname(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("atom input", () => {
      const filename = Type.atom("file");
      const result = dirname(filename);
      const expected = Type.charlist(".");

      assert.deepStrictEqual(result, expected);
    });

    it("atom input with path", () => {
      const filename = Type.atom("foo/bar");
      const result = dirname(filename);
      const expected = Type.charlist("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("list input", () => {
      const filename = Type.list([
        Type.integer(102),
        Type.integer(111),
        Type.integer(111),
      ]); // "foo"

      const result = dirname(filename);
      const expected = Type.list([Type.integer(46)]); // "."

      assert.deepStrictEqual(result, expected);
    });

    it("iolist input with path", () => {
      const filename = Type.list([
        Type.bitstring("foo/"),
        Type.integer(98),
        Type.integer(97),
        Type.integer(114),
      ]); // "foo/bar"

      const result = dirname(filename);
      const expected = Type.charlist("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("empty list input", () => {
      const emptyList = Type.list();
      const result = dirname(emptyList);
      const expected = Type.charlist(".");

      assert.deepStrictEqual(result, expected);
    });

    it("multiple trailing slashes", () => {
      const filename = Type.bitstring("foo/bar///");
      const result = dirname(filename);
      const expected = Type.bitstring("foo/bar");

      assert.deepStrictEqual(result, expected);
    });

    it("handles invalid UTF-8 binary", () => {
      const filename = Bitstring.fromBytes(new Uint8Array([255, 47, 254]));
      const result = dirname(filename);

      assert.deepStrictEqual(result.bytes, new Uint8Array([255]));
    });

    it("handles invalid UTF-8 list", () => {
      const filename = Type.list([
        Type.integer(255),
        Type.integer(47),
        Type.integer(254),
      ]);

      const result = dirname(filename);
      const expected = Type.list([Type.integer(255)]);

      assert.deepStrictEqual(result, expected);
    });

    it("invalid UTF-8 with no separator", () => {
      const filename = Bitstring.fromBytes(new Uint8Array([255, 254, 253]));
      const result = dirname(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("invalid UTF-8 with trailing separators", () => {
      const filename = Bitstring.fromBytes(new Uint8Array([255, 47, 47]));
      const result = dirname(filename);

      assert.deepStrictEqual(result.bytes, new Uint8Array([255]));
    });

    it("raises FunctionClauseError if the argument is not a bitstring or atom or list", () => {
      const arg = Type.integer(123);

      assertBoxedError(
        () => dirname(arg),
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
        () => dirname(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg,
          Type.list(),
        ]),
      );
    });
  });

  describe("extension/1", () => {
    const extension = Erlang_Filename["extension/1"];

    it("file with extension", () => {
      const filename = Type.bitstring("foo.erl");
      const result = extension(filename);
      const expected = Type.bitstring(".erl");

      assert.deepStrictEqual(result, expected);
    });

    it("file without extension", () => {
      const filename = Type.bitstring("foo");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("file with path and extension", () => {
      const filename = Type.bitstring("path/to/file.txt");
      const result = extension(filename);
      const expected = Type.bitstring(".txt");

      assert.deepStrictEqual(result, expected);
    });

    it("file with multiple dots in filename", () => {
      const filename = Type.bitstring("archive.tar.gz");
      const result = extension(filename);
      const expected = Type.bitstring(".gz");

      assert.deepStrictEqual(result, expected);
    });

    it("file starting with dot", () => {
      const filename = Type.bitstring(".hidden");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("directory path without extension", () => {
      const filename = Type.bitstring("beam.src/kalle");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("absolute path with extension", () => {
      const filename = Type.bitstring("/usr/local/foo.txt");
      const result = extension(filename);
      const expected = Type.bitstring(".txt");

      assert.deepStrictEqual(result, expected);
    });

    it("empty string", () => {
      const filename = Type.bitstring("");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("path with trailing slash", () => {
      const filename = Type.bitstring("path/to/dir/");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("file with dot in directory name", () => {
      const filename = Type.bitstring("path.dir/file");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("file with multiple dots including in directory", () => {
      const filename = Type.bitstring("path.dir/file.tar.gz");
      const result = extension(filename);
      const expected = Type.bitstring(".gz");

      assert.deepStrictEqual(result, expected);
    });

    it("atom input with extension", () => {
      const filename = Type.atom("file.txt");
      const result = extension(filename);
      const expected = Type.charlist(".txt");

      assert.deepStrictEqual(result, expected);
    });

    it("atom input without extension", () => {
      const filename = Type.atom("file");
      const result = extension(filename);
      const expected = Type.charlist("");

      assert.deepStrictEqual(result, expected);
    });

    it("empty list input", () => {
      const emptyList = Type.list();
      const result = extension(emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("iolist input with extension", () => {
      const filename = Type.list([
        Type.charlist("path/to/"),
        Type.integer(102), // 'f'
        Type.integer(105), // 'i'
        Type.integer(108), // 'l'
        Type.integer(101), // 'e'
        Type.charlist(".txt"),
      ]);

      const result = extension(filename);
      const expected = Type.charlist(".txt");

      assert.deepStrictEqual(result, expected);
    });

    it("bitstring input", () => {
      // "file.txt"
      const filename = Bitstring.fromBytes([
        102, 105, 108, 101, 46, 116, 120, 116,
      ]);

      const result = extension(filename);
      const expected = Type.bitstring(".txt");

      assert.deepStrictEqual(result, expected);
    });

    it("handles invalid UTF-8 binary", () => {
      const filename = Bitstring.fromBytes(new Uint8Array([255, 46, 254]));
      const result = extension(filename);

      assert.deepStrictEqual(result.bytes, new Uint8Array([46, 254]));
    });

    it("handles invalid UTF-8 iolist", () => {
      const filename = Type.list([
        Type.integer(255),
        Type.integer(46),
        Type.integer(254),
      ]);

      const result = extension(filename);
      const expected = Type.list([Type.integer(46), Type.integer(254)]);

      assert.deepStrictEqual(result, expected);
    });

    it("trailing dot is a valid extension", () => {
      const filename = Type.bitstring("file.");
      const result = extension(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("hidden file with extension", () => {
      const filename = Type.bitstring(".hidden.txt");
      const result = extension(filename);
      const expected = Type.bitstring(".txt");

      assert.deepStrictEqual(result, expected);
    });

    it("double dot", () => {
      const filename = Type.bitstring("..");
      const result = extension(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("root path", () => {
      const filename = Type.bitstring("/");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("current directory", () => {
      const filename = Type.bitstring(".");
      const result = extension(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a bitstring or atom or list", () => {
      const arg = Type.integer(123);

      assertBoxedError(
        () => extension(arg),
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
        () => extension(arg),
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

  describe("join/1", () => {
    const join = Erlang_Filename["join/1"];

    it("joins multiple path components", () => {
      const components = Type.list([
        Type.bitstring("usr"),
        Type.bitstring("local"),
        Type.bitstring("bin"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("usr/local/bin");

      assert.deepStrictEqual(result, expected);
    });

    it("joins components with leading slash", () => {
      const components = Type.list([
        Type.bitstring("/usr"),
        Type.bitstring("local"),
        Type.bitstring("bin"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("/usr/local/bin");

      assert.deepStrictEqual(result, expected);
    });

    it("normalizes path with redundant slashes", () => {
      const components = Type.list([Type.bitstring("a/b///c/")]);
      const result = join(components);
      const expected = Type.bitstring("a/b/c");

      assert.deepStrictEqual(result, expected);
    });

    it("handles single component", () => {
      const components = Type.list([Type.bitstring("foo")]);
      const result = join(components);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("handles absolute path in middle component", () => {
      const components = Type.list([
        Type.bitstring("usr"),
        Type.bitstring("/local"),
        Type.bitstring("bin"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("/local/bin");

      assert.deepStrictEqual(result, expected);
    });

    it("handles trailing slashes", () => {
      const components = Type.list([
        Type.bitstring("a/"),
        Type.bitstring("b"),
        Type.bitstring("c"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("a/b/c");

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty string components", () => {
      const components = Type.list([
        Type.bitstring(""),
        Type.bitstring(""),
        Type.bitstring(""),
      ]);

      const result = join(components);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("handles dot components", () => {
      const components = Type.list([
        Type.bitstring("."),
        Type.bitstring("local"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("./local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles parent directory references", () => {
      const components = Type.list([
        Type.bitstring(".."),
        Type.bitstring("usr"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("../usr");

      assert.deepStrictEqual(result, expected);
    });

    it("handles atom components", () => {
      const components = Type.list([Type.atom("foo"), Type.atom("bar")]);
      const result = join(components);
      const expected = Type.charlist("foo/bar");

      assert.deepStrictEqual(result, expected);
    });

    it("handles nested list components", () => {
      const components = Type.list([
        Type.list([Type.bitstring("a"), Type.bitstring("b")]),
        Type.bitstring("c"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("ab/c");

      assert.deepStrictEqual(result, expected);
    });

    it("handles iolist components", () => {
      const components = Type.list([
        Type.list([
          Type.integer(117), // 'u'
          Type.integer(115), // 's'
          Type.integer(114), // 'r'
        ]),
        Type.bitstring("local"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles root with additional components", () => {
      const components = Type.list([
        Type.bitstring("/"),
        Type.bitstring("usr"),
        Type.bitstring("local"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("/usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles multiple consecutive slashes", () => {
      const components = Type.list([
        Type.bitstring("//usr"),
        Type.bitstring("local"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("/usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("preserves invalid UTF-8 bytes in binary components", () => {
      const invalid = Bitstring.fromBytes([0xc3, 0x28]); // invalid 2-byte sequence
      Bitstring.maybeSetTextFromBytes(invalid);

      const components = Type.list([
        Type.bitstring("usr"),
        invalid,
        Type.bitstring("bin"),
      ]);

      const result = join(components);

      const expected = Bitstring.fromBytes([
        117, 115, 114, 47, 0xc3, 0x28, 47, 98, 105, 110,
      ]);

      Bitstring.maybeSetTextFromBytes(expected);

      assert.deepStrictEqual(result, expected);
    });

    it("handles single absolute component", () => {
      const components = Type.list([Type.bitstring("/usr/local/bin")]);
      const result = join(components);
      const expected = Type.bitstring("/usr/local/bin");

      assert.deepStrictEqual(result, expected);
    });

    it("handles single root component", () => {
      const components = Type.list([Type.bitstring("/")]);
      const result = join(components);
      const expected = Type.bitstring("/");

      assert.deepStrictEqual(result, expected);
    });

    it("handles deeply nested iolist components", () => {
      const components = Type.list([
        Type.list([Type.list([Type.bitstring("a")])]),
        Type.bitstring("b"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("a/b");

      assert.deepStrictEqual(result, expected);
    });

    it("handles mixed types with absolute path override", () => {
      const components = Type.list([
        Type.bitstring("usr"),
        Type.bitstring("local"),
        Type.bitstring("/tmp"),
        Type.bitstring("file"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("/tmp/file");

      assert.deepStrictEqual(result, expected);
    });

    it("handles multiple atoms and binaries", () => {
      const components = Type.list([
        Type.atom("home"),
        Type.bitstring("user"),
        Type.atom("documents"),
      ]);

      const result = join(components);
      const expected = Type.bitstring("home/user/documents");

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      const arg = Type.bitstring("not-a-list");

      assertBoxedError(
        () => join(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.join/1", [arg]),
      );
    });

    it("raises FunctionClauseError if list is empty", () => {
      const arg = Type.list([]);

      assertBoxedError(
        () => join(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.join/1", [arg]),
      );
    });
  });

  describe("join/2", () => {
    const join = Erlang_Filename["join/2"];

    it("joins two path components", () => {
      const name1 = Type.bitstring("usr");
      const name2 = Type.bitstring("local");
      const result = join(name1, name2);
      const expected = Type.bitstring("usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles absolute first component", () => {
      const name1 = Type.bitstring("/usr");
      const name2 = Type.bitstring("local");
      const result = join(name1, name2);
      const expected = Type.bitstring("/usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles absolute second component", () => {
      const name1 = Type.bitstring("usr");
      const name2 = Type.bitstring("/local");
      const result = join(name1, name2);
      const expected = Type.bitstring("/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty first component", () => {
      const name1 = Type.bitstring("");
      const name2 = Type.bitstring("local");
      const result = join(name1, name2);
      const expected = Type.bitstring("/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty second component", () => {
      const name1 = Type.bitstring("usr");
      const name2 = Type.bitstring("");
      const result = join(name1, name2);
      const expected = Type.bitstring("usr");

      assert.deepStrictEqual(result, expected);
    });

    it("handles both empty components", () => {
      const name1 = Type.bitstring("");
      const name2 = Type.bitstring("");
      const result = join(name1, name2);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("handles trailing slash in first component", () => {
      const name1 = Type.bitstring("usr/");
      const name2 = Type.bitstring("local");
      const result = join(name1, name2);
      const expected = Type.bitstring("usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles absolute second component with trailing slash in first", () => {
      const name1 = Type.bitstring("usr/");
      const name2 = Type.bitstring("/local");
      const result = join(name1, name2);
      const expected = Type.bitstring("/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles atom inputs", () => {
      const name1 = Type.atom("foo");
      const name2 = Type.atom("bar");
      const result = join(name1, name2);
      const expected = Type.charlist("foo/bar");

      assert.deepStrictEqual(result, expected);
    });

    it("handles mixed atom and binary inputs", () => {
      const name1 = Type.atom("foo");
      const name2 = Type.bitstring("bar");
      const result = join(name1, name2);
      const expected = Type.bitstring("foo/bar");

      assert.deepStrictEqual(result, expected);
    });

    it("handles list input for first component", () => {
      const name1 = Type.list([
        Type.integer(117),
        Type.integer(115),
        Type.integer(114),
      ]); // 'usr'

      const name2 = Type.bitstring("local");
      const result = join(name1, name2);
      const expected = Type.bitstring("usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles list input for second component", () => {
      const name1 = Type.bitstring("usr");
      const name2 = Type.list([
        Type.integer(108),
        Type.integer(111),
        Type.integer(99),
        Type.integer(97),
        Type.integer(108),
      ]); // 'local'

      const result = join(name1, name2);
      const expected = Type.bitstring("usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles iolist inputs", () => {
      const name1 = Type.list([
        Type.list([Type.integer(117), Type.integer(115), Type.integer(114)]),
      ]); // [[?u, ?s, ?r]]

      const name2 = Type.list([
        Type.list([
          Type.integer(108),
          Type.integer(111),
          Type.integer(99),
          Type.integer(97),
          Type.integer(108),
        ]),
      ]); // [[?l, ?o, ?c, ?a, ?l]]

      const result = join(name1, name2);
      const expected = Type.charlist("usr/local");

      assert.deepStrictEqual(result, expected);
    });

    it("normalizes redundant slashes", () => {
      const name1 = Type.bitstring("usr//");
      const name2 = Type.bitstring("//local");
      const result = join(name1, name2);
      const expected = Type.bitstring("/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles dot in paths", () => {
      const name1 = Type.bitstring(".");
      const name2 = Type.bitstring("local");
      const result = join(name1, name2);
      const expected = Type.bitstring("./local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles parent directory reference", () => {
      const name1 = Type.bitstring("usr");
      const name2 = Type.bitstring("../local");
      const result = join(name1, name2);
      const expected = Type.bitstring("usr/../local");

      assert.deepStrictEqual(result, expected);
    });

    it("preserves invalid UTF-8 bytes in binary inputs", () => {
      const invalidBytes = [0xc3, 0x28]; // invalid 2-byte UTF-8 sequence
      const name1 = Type.bitstring("usr");

      const name2 = Bitstring.fromBytes(invalidBytes);
      Bitstring.maybeSetTextFromBytes(name2);

      const result = join(name1, name2);

      const expected = Bitstring.fromBytes([
        117,
        115,
        114,
        47,
        ...invalidBytes,
      ]);

      Bitstring.maybeSetTextFromBytes(expected);

      assert.deepStrictEqual(result, expected);
    });

    it("handles both components as slash", () => {
      const name1 = Type.bitstring("/");
      const name2 = Type.bitstring("/");
      const result = join(name1, name2);
      const expected = Type.bitstring("/");

      assert.deepStrictEqual(result, expected);
    });

    it("handles slash with empty", () => {
      const name1 = Type.bitstring("/");
      const name2 = Type.bitstring("");
      const result = join(name1, name2);
      const expected = Type.bitstring("/");

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty with slash", () => {
      const name1 = Type.bitstring("");
      const name2 = Type.bitstring("/");
      const result = join(name1, name2);
      const expected = Type.bitstring("/");

      assert.deepStrictEqual(result, expected);
    });

    it("handles multiple absolute path components", () => {
      const name1 = Type.bitstring("/usr");
      const name2 = Type.bitstring("/local");
      const result = join(name1, name2);
      const expected = Type.bitstring("/local");

      assert.deepStrictEqual(result, expected);
    });

    it("handles complex path with dots", () => {
      const name1 = Type.bitstring("./foo");
      const name2 = Type.bitstring("bar/./baz");
      const result = join(name1, name2);
      const expected = Type.bitstring("./foo/bar/baz");

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if first argument is invalid", () => {
      const arg1 = Type.integer(123);
      const arg2 = Type.bitstring("local");

      assertBoxedError(
        () => join(arg1, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.join/2", [
          arg1,
          arg2,
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is invalid", () => {
      const arg1 = Type.bitstring("usr");
      const arg2 = Type.integer(123);

      assertBoxedError(
        () => join(arg1, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.join/2", [
          arg1,
          arg2,
        ]),
      );
    });
  });

  describe("rootname/1", () => {
    const rootname = Erlang_Filename["rootname/1"];

    it("path with extension", () => {
      const filename = Type.bitstring("/jam.src/foo.erl");
      const result = rootname(filename);
      const expected = Type.bitstring("/jam.src/foo");

      assert.deepStrictEqual(result, expected);
    });

    it("path without extension", () => {
      const filename = Type.bitstring("/jam.src/kalle");
      const result = rootname(filename);
      const expected = Type.bitstring("/jam.src/kalle");

      assert.deepStrictEqual(result, expected);
    });

    it("filename with extension", () => {
      const filename = Type.bitstring("foo.erl");
      const result = rootname(filename);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("filename without extension", () => {
      const filename = Type.bitstring("foo");
      const result = rootname(filename);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("filename starting with dot", () => {
      const filename = Type.bitstring(".foo");
      const result = rootname(filename);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("filename with multiple extensions", () => {
      const filename = Type.bitstring("foo.bar.baz");
      const result = rootname(filename);
      const expected = Type.bitstring("foo.bar");

      assert.deepStrictEqual(result, expected);
    });

    it("path with hidden file", () => {
      const filename = Type.bitstring("path/to/.hidden");
      const result = rootname(filename);
      const expected = Type.bitstring("path/to/.hidden");

      assert.deepStrictEqual(result, expected);
    });

    it("root path", () => {
      const filename = Type.bitstring("/");
      const result = rootname(filename);
      const expected = Type.bitstring("/");

      assert.deepStrictEqual(result, expected);
    });

    it("empty string", () => {
      const emptyString = Type.bitstring("");
      const result = rootname(emptyString);

      assert.deepStrictEqual(result, emptyString);
    });

    it("path ending with dot", () => {
      const filename = Type.bitstring("foo.");
      const result = rootname(filename);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("hidden file in root", () => {
      const filename = Type.bitstring("/.bashrc");
      const result = rootname(filename);
      const expected = Type.bitstring("/.bashrc");

      assert.deepStrictEqual(result, expected);
    });

    it("hidden file in subdirectory", () => {
      const filename = Type.bitstring("/foo/.bashrc");
      const result = rootname(filename);
      const expected = Type.bitstring("/foo/.bashrc");

      assert.deepStrictEqual(result, expected);
    });

    it("hidden file with extension", () => {
      const filename = Type.bitstring(".bashrc.bak");
      const result = rootname(filename);
      const expected = Type.bitstring(".bashrc");

      assert.deepStrictEqual(result, expected);
    });

    it("hidden file in subdirectory with extension", () => {
      const filename = Type.bitstring("/foo/.bashrc.bak");
      const result = rootname(filename);
      const expected = Type.bitstring("/foo/.bashrc");

      assert.deepStrictEqual(result, expected);
    });

    it("empty list input", () => {
      const emptyList = Type.list();
      const result = rootname(emptyList);

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

      const result = rootname(filename);
      const expected = Type.charlist("path/to/file");

      assert.deepStrictEqual(result, expected);
    });

    it("handles invalid UTF-8 bytewise (raw filename)", () => {
      // Invalid UTF-8 bytes: <<255, 254, 253>>
      const invalidUtf8 = Bitstring.fromBytes(new Uint8Array([255, 254, 253]));

      const result = rootname(invalidUtf8);

      // Should return unchanged since no extension
      assert.deepStrictEqual(result.bytes, invalidUtf8.bytes);
    });

    it("removes extension from invalid UTF-8 filename", () => {
      // Invalid UTF-8 with extension: <<255, 254, 46, 253>> (0xFF 0xFE '.' 0xFD)
      const invalidUtf8WithExt = Bitstring.fromBytes(
        new Uint8Array([255, 254, 46, 253]),
      );

      const result = rootname(invalidUtf8WithExt);

      // Should remove ".253" (last dot and everything after)
      const expected = new Uint8Array([255, 254]);

      assert.deepStrictEqual(result.bytes, expected);
    });

    it("preserves invalid UTF-8 hidden file", () => {
      // Invalid UTF-8 starting with slash-dot: <<47, 46, 255, 254>> ('/' '.' 0xFF 0xFE)
      const invalidUtf8Hidden = Bitstring.fromBytes(
        new Uint8Array([47, 46, 255, 254]),
      );

      const result = rootname(invalidUtf8Hidden);

      // Should not remove extension after slash
      assert.deepStrictEqual(result.bytes, invalidUtf8Hidden.bytes);
    });

    it("filename with trailing slash", () => {
      const filename = Type.bitstring("foo.txt/");
      const result = rootname(filename);
      const expected = Type.bitstring("foo.txt/");

      assert.deepStrictEqual(result, expected);
    });

    it("filename with double dots as extension", () => {
      const filename = Type.bitstring("foo..txt");
      const result = rootname(filename);
      const expected = Type.bitstring("foo.");

      assert.deepStrictEqual(result, expected);
    });

    it("filename is just double dots", () => {
      const filename = Type.bitstring("..");
      const result = rootname(filename);
      const expected = Type.bitstring(".");

      assert.deepStrictEqual(result, expected);
    });

    it("filename is three dots", () => {
      const filename = Type.bitstring("...");
      const result = rootname(filename);
      const expected = Type.bitstring("..");

      assert.deepStrictEqual(result, expected);
    });

    it("atom input", () => {
      const filename = Type.atom("/jam.src/foo.erl");
      const result = rootname(filename);
      const expected = Type.charlist("/jam.src/foo");

      assert.deepStrictEqual(result, expected);
    });

    it("iolist with invalid UTF-8 bytes", () => {
      // Charlist with invalid UTF-8: [47, 102, 111, 111, 46, 0xFF, 0xFE]
      // "/foo." + [0xFF, 0xFE]
      const filename = Type.list([
        Type.integer(47), // '/'
        Type.integer(102), // 'f'
        Type.integer(111), // 'o'
        Type.integer(111), // 'o'
        Type.integer(46), // '.'
        Type.integer(0xff),
        Type.integer(0xfe),
      ]);

      const result = rootname(filename);

      // Should return the root without the extension [0xFF, 0xFE]
      // Result: [47, 102, 111, 111]
      const expected = Type.list([
        Type.integer(47), // '/'
        Type.integer(102), // 'f'
        Type.integer(111), // 'o'
        Type.integer(111), // 'o'
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a bitstring or atom or list", () => {
      const arg = Type.integer(123);

      assertBoxedError(
        () => rootname(arg),
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
        () => rootname(arg),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg,
          Type.list(),
        ]),
      );
    });
  });

  describe("rootname/2", () => {
    const rootname = Erlang_Filename["rootname/2"];

    it("removes matching extension", () => {
      const filename = Type.bitstring("/jam.src/foo.erl");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("/jam.src/foo");

      assert.deepStrictEqual(result, expected);
    });

    it("does not remove non-matching extension", () => {
      const filename = Type.bitstring("/jam.src/kalle.jam");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("/jam.src/kalle.jam");

      assert.deepStrictEqual(result, expected);
    });

    it("removes partial extension match", () => {
      const filename = Type.bitstring("/jam.src/kalle.old.erl");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("/jam.src/kalle.old");

      assert.deepStrictEqual(result, expected);
    });

    it("removes extension from filename only", () => {
      const filename = Type.bitstring("foo.erl");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("does not remove if filename does not match extension", () => {
      const filename = Type.bitstring("foo.beam");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo.beam");

      assert.deepStrictEqual(result, expected);
    });

    it("removes extension when filename equals extension", () => {
      const filename = Type.bitstring(".bashrc");
      const ext = Type.bitstring(".bashrc");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("does not remove extension after slash in root", () => {
      const filename = Type.bitstring("/.erl");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("/.erl");

      assert.deepStrictEqual(result, expected);
    });

    it("does not remove extension after slash in subdirectory", () => {
      const filename = Type.bitstring("/path/.erl");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("/path/.erl");

      assert.deepStrictEqual(result, expected);
    });

    it("empty extension", () => {
      const filename = Type.bitstring("foo.erl");
      const ext = Type.bitstring("");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo.erl");

      assert.deepStrictEqual(result, expected);
    });

    it("empty filename", () => {
      const filename = Type.bitstring("");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("empty list filename input", () => {
      const emptyList = Type.list();
      const ext = Type.bitstring(".erl");
      const result = rootname(emptyList, ext);
      const expected = Type.bitstring("");

      assert.deepStrictEqual(result, expected);
    });

    it("iolist filename input", () => {
      const filename = Type.list([
        Type.bitstring("foo"),
        Type.bitstring(".erl"),
      ]);

      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("iolist extension input", () => {
      const filename = Type.bitstring("foo.erl");
      const ext = Type.list([Type.bitstring("."), Type.bitstring("erl")]);
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("handles invalid UTF-8 filename bytewise (raw filename)", () => {
      // Invalid UTF-8 bytes: <<255, 254, 253>>
      const invalidUtf8 = Bitstring.fromBytes(new Uint8Array([255, 254, 253]));

      const ext = Bitstring.fromBytes(new Uint8Array([253])); // <<253>>

      const result = rootname(invalidUtf8, ext);

      // Should remove the last byte (253)
      const expected = new Uint8Array([255, 254]);

      assert.deepStrictEqual(result.bytes, expected);
    });

    it("handles invalid UTF-8 extension bytewise", () => {
      const filename = Type.bitstring("foo.erl");

      // Invalid UTF-8 extension
      const invalidExt = Bitstring.fromBytes(new Uint8Array([255, 254]));

      const result = rootname(filename, invalidExt);

      // Should not remove anything (extension doesn't match)
      assertBoxedStrictEqual(result, filename);
    });

    it("handles both filename and extension as invalid UTF-8", () => {
      // Filename: <<255, 254, 46, 253>> (0xFF 0xFE '.' 0xFD)
      const invalidFilename = Bitstring.fromBytes(
        new Uint8Array([255, 254, 46, 253]),
      );

      // Extension: <<46, 253>> ('.' 0xFD)
      const invalidExt = Bitstring.fromBytes(new Uint8Array([46, 253]));

      const result = rootname(invalidFilename, invalidExt);

      // Should remove the matching extension
      const expected = new Uint8Array([255, 254]);

      assert.deepStrictEqual(result.bytes, expected);
    });

    it("does not remove invalid UTF-8 extension after slash", () => {
      // Filename: <<47, 255, 254>> ('/' 0xFF 0xFE)
      const invalidFilename = Bitstring.fromBytes(
        new Uint8Array([47, 255, 254]),
      );

      // Extension: <<255, 254>> (0xFF 0xFE)
      const invalidExt = Bitstring.fromBytes(new Uint8Array([255, 254]));

      const result = rootname(invalidFilename, invalidExt);

      // Should not remove (extension is right after slash)
      assert.deepStrictEqual(result.bytes, invalidFilename.bytes);
    });

    it("extension without leading dot", () => {
      const filename = Type.bitstring("foo.erl");
      const ext = Type.bitstring("erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo.");

      assert.deepStrictEqual(result, expected);
    });

    it("extension longer than filename", () => {
      const filename = Type.bitstring("foo");
      const ext = Type.bitstring("foobar");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("extension with double dots", () => {
      const filename = Type.bitstring("foo.erl");
      const ext = Type.bitstring("..erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo.erl");

      assert.deepStrictEqual(result, expected);
    });

    it("atom filename input", () => {
      const filename = Type.atom("foo.erl");
      const ext = Type.bitstring(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("atom extension input", () => {
      const filename = Type.bitstring("foo.erl");
      const ext = Type.atom(".erl");
      const result = rootname(filename, ext);
      const expected = Type.bitstring("foo");

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not a bitstring or atom or list", () => {
      const arg1 = Type.integer(123);
      const arg2 = Type.bitstring(".erl");

      assertBoxedError(
        () => rootname(arg1, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg1,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the first argument is a non-binary bitstring", () => {
      const arg1 = Type.bitstring([1, 0, 1]);
      const arg2 = Type.bitstring(".erl");

      assertBoxedError(
        () => rootname(arg1, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg1,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument is not a bitstring or atom or list", () => {
      const arg1 = Type.bitstring("foo.erl");
      const arg2 = Type.integer(123);

      assertBoxedError(
        () => rootname(arg1, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg2,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument is a non-binary bitstring", () => {
      const arg1 = Type.bitstring("foo.erl");
      const arg2 = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => rootname(arg1, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          arg2,
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
      const expected = Type.list();

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
      const filename = Type.list();
      const result = split(filename);
      const expected = Type.list();

      assert.deepStrictEqual(result, expected);
    });

    it("iolist input", () => {
      const filename = Type.list([
        Type.charlist("foo"),
        Type.integer(47), // '/'
        Type.charlist("bar"),
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

      const invalidUtf8Part = Bitstring.fromBytes([0xff, 0xfe]);
      Bitstring.maybeSetTextFromBytes(invalidUtf8Part);

      // Should preserve invalid UTF-8 bytes
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
          Type.list(),
        ]),
      );
    });
  });
});
