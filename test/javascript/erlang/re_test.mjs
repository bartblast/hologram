"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Re from "../../../assets/js/erlang/re.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/re_test.exs
// Always update both together.

const assertCompileErrorTuple = (result, message, position) => {
  assert.deepEqual(
    result,
    Type.tuple([
      Type.atom("error"),
      Type.tuple([Type.charlist(message), Type.integer(position)]),
    ]),
  );
};

// Asserts an {:ok, {:re_pattern, _, _, _, ref}} result and returns the ref.
const assertOkResult = (result, captureCount, unicodeFlag, useCrlf) => {
  assert.isTrue(Type.isTuple(result));
  assert.equal(result.data.length, 2);
  assert.deepEqual(result.data[0], Type.atom("ok"));

  return assertRePattern(result.data[1], captureCount, unicodeFlag, useCrlf);
};

// Asserts a {:re_pattern, _, _, _, ref} tuple and returns the ref.
const assertRePattern = (rePattern, captureCount, unicodeFlag, useCrlf) => {
  assert.isTrue(Type.isTuple(rePattern));
  assert.equal(rePattern.data.length, 5);
  assert.deepEqual(rePattern.data[0], Type.atom("re_pattern"));
  assert.deepEqual(rePattern.data[1], Type.integer(captureCount));
  assert.deepEqual(rePattern.data[2], Type.integer(unicodeFlag));
  assert.deepEqual(rePattern.data[3], Type.integer(useCrlf));
  assert.isTrue(Type.isReference(rePattern.data[4]));

  return rePattern.data[4];
};

describe("Erlang_Re", () => {
  describe("compile/1", () => {
    const compile = Erlang_Re["compile/1"];

    it("compiles a pattern with default options", () => {
      const result = compile(Type.bitstring("(a)b"));

      assertOkResult(result, 1, 0, 0);
    });

    it("returns a compile error tuple on invalid pattern", () => {
      const result = compile(Type.bitstring("a{2,1}"));

      assertCompileErrorTuple(
        result,
        "numbers out of order in {} quantifier",
        5,
      );
    });

    it("raises ArgumentError on non-iodata pattern", () => {
      assertBoxedError(
        () => compile(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });
  });

  describe("compile/2", () => {
    const compile = Erlang_Re["compile/2"];

    const compileWithOpts = (pattern, opts) =>
      compile(pattern, Type.list(opts));

    it("compiles a binary pattern", () => {
      const result = compileWithOpts(Type.bitstring("ab"), []);

      assertOkResult(result, 0, 0, 0);
    });

    it("compiles a charlist pattern", () => {
      const result = compileWithOpts(Type.charlist("ab"), []);

      assertOkResult(result, 0, 0, 0);
    });

    it("compiles nested iodata with an improper binary tail", () => {
      const pattern = Type.improperList([
        Type.charlist("a("),
        Type.bitstring("b)"),
        Type.bitstring("c"),
      ]);

      const result = compileWithOpts(pattern, []);

      assertOkResult(result, 1, 0, 0);
    });

    it("compiles an empty pattern", () => {
      const result = compileWithOpts(Type.bitstring(""), []);

      assertOkResult(result, 0, 0, 0);
    });

    it("counts capture groups", () => {
      const result = compileWithOpts(Type.bitstring("(a)(b)(?<n>c)"), []);

      assertOkResult(result, 3, 0, 0);
    });

    it("counts branch reset groups with shared numbers", () => {
      const result = compileWithOpts(Type.bitstring("(?|(a)|(b))"), []);

      assertOkResult(result, 1, 0, 0);
    });

    it("sets the unicode flag with the unicode option", () => {
      const result = compileWithOpts(Type.bitstring("ab"), [
        Type.atom("unicode"),
      ]);

      assertOkResult(result, 0, 1, 0);
    });

    it("doesn't set the unicode flag with a UTF pattern verb", () => {
      const result = compileWithOpts(Type.bitstring("(*UTF)ab"), []);

      assertOkResult(result, 0, 0, 0);
    });

    it("decodes a UTF-8 binary pattern with the unicode option", () => {
      const result = compileWithOpts(Type.bitstring("é{2}"), [
        Type.atom("unicode"),
      ]);

      assertOkResult(result, 0, 1, 0);
    });

    it("decodes byte input as UTF-8 with a UTF pattern verb", () => {
      const result = compileWithOpts(Type.bitstring("(*UTF)é{2}"), []);

      assertOkResult(result, 0, 0, 0);
    });

    it("treats bytes as latin-1 without the unicode option", () => {
      const result = compileWithOpts(Bitstring.fromBytes([233, 255]), []);

      assertOkResult(result, 0, 0, 0);
    });

    it("accepts unicode char data with the unicode option", () => {
      const pattern = Type.list([Type.integer(233), Type.bitstring("é")]);

      const result = compileWithOpts(pattern, [Type.atom("unicode")]);

      assertOkResult(result, 0, 1, 0);
    });

    it("sets the use_crlf flag with a crlf newline option", () => {
      const result = compileWithOpts(Type.bitstring("ab"), [
        Type.tuple([Type.atom("newline"), Type.atom("crlf")]),
      ]);

      assertOkResult(result, 0, 0, 1);
    });

    it("sets the use_crlf flag with an any newline option", () => {
      const result = compileWithOpts(Type.bitstring("ab"), [
        Type.tuple([Type.atom("newline"), Type.atom("any")]),
      ]);

      assertOkResult(result, 0, 0, 1);
    });

    it("doesn't set the use_crlf flag with a cr newline option", () => {
      const result = compileWithOpts(Type.bitstring("ab"), [
        Type.tuple([Type.atom("newline"), Type.atom("cr")]),
      ]);

      assertOkResult(result, 0, 0, 0);
    });

    it("sets the use_crlf flag with a newline verb", () => {
      const result = compileWithOpts(Type.bitstring("(*CRLF)ab"), []);

      assertOkResult(result, 0, 0, 1);
    });

    it("newline verb beats the newline option", () => {
      const result = compileWithOpts(Type.bitstring("(*LF)ab"), [
        Type.tuple([Type.atom("newline"), Type.atom("crlf")]),
      ]);

      assertOkResult(result, 0, 0, 0);
    });

    it("last newline option wins", () => {
      const result = compileWithOpts(Type.bitstring("ab"), [
        Type.tuple([Type.atom("newline"), Type.atom("crlf")]),
        Type.tuple([Type.atom("newline"), Type.atom("lf")]),
      ]);

      assertOkResult(result, 0, 0, 0);
    });

    it("last newline verb wins", () => {
      const result = compileWithOpts(Type.bitstring("(*CRLF)(*LF)ab"), []);

      assertOkResult(result, 0, 0, 0);
    });

    it("accepts all compile options", () => {
      const opts = [
        "anchored",
        "bsr_anycrlf",
        "bsr_unicode",
        "caseless",
        "dollar_endonly",
        "dotall",
        "dupnames",
        "extended",
        "firstline",
        "multiline",
        "no_auto_capture",
        "no_start_optimize",
        "ucp",
        "ungreedy",
      ].map(Type.atom);

      const result = compileWithOpts(Type.bitstring("ab"), opts);

      assertOkResult(result, 0, 0, 0);
    });

    it("accepts duplicated options", () => {
      const result = compileWithOpts(Type.bitstring("ab"), [
        Type.atom("caseless"),
        Type.atom("caseless"),
      ]);

      assertOkResult(result, 0, 0, 0);
    });

    // Client-only mechanics, no Elixir consistency test counterpart
    it("stores the compiled pattern in the registry", () => {
      const result = compileWithOpts(Type.bitstring("ab"), []);
      const ref = assertOkResult(result, 0, 0, 0);

      assert.isNotNull(ERTS.regexPatternRegistry.get(ref));
    });

    it("returns a compile error tuple on invalid pattern", () => {
      const result = compileWithOpts(Type.bitstring("a{2,1}"), []);

      assertCompileErrorTuple(
        result,
        "numbers out of order in {} quantifier",
        5,
      );
    });

    it("returns error position as byte offset in unicode mode", () => {
      const result = compileWithOpts(Type.bitstring("é("), [
        Type.atom("unicode"),
      ]);

      assertCompileErrorTuple(result, "missing closing parenthesis", 3);
    });

    it("returns a UTF-8 error tuple for invalid UTF-8 binary in unicode mode", () => {
      const result = compileWithOpts(Bitstring.fromBytes([255, 97]), [
        Type.atom("unicode"),
      ]);

      assertCompileErrorTuple(
        result,
        "UTF-8 error: illegal byte (0xfe or 0xff)",
        0,
      );
    });

    it("returns a UTF-8 error tuple for invalid UTF-8 after a UTF pattern verb", () => {
      const pattern = Type.improperList([
        Type.bitstring("(*UTF)"),
        Bitstring.fromBytes([255]),
      ]);

      const result = compileWithOpts(pattern, []);

      assertCompileErrorTuple(
        result,
        "UTF-8 error: illegal byte (0xfe or 0xff)",
        6,
      );
    });

    it("returns a disabled UTF error with never_utf option and a UTF pattern verb", () => {
      const result = compileWithOpts(Type.bitstring("(*UTF)ab"), [
        Type.atom("never_utf"),
      ]);

      assertCompileErrorTuple(
        result,
        "using UTF is disabled by the application",
        6,
      );
    });

    it("disabled UTF error beats UTF-8 validation", () => {
      const pattern = Type.improperList([
        Type.bitstring("(*UTF)"),
        Bitstring.fromBytes([255]),
      ]);

      const result = compileWithOpts(pattern, [Type.atom("never_utf")]);

      assertCompileErrorTuple(
        result,
        "using UTF is disabled by the application",
        6,
      );
    });

    it("returns a disabled UTF error with unicode and never_utf options", () => {
      const result = compileWithOpts(Type.bitstring("ab"), [
        Type.atom("unicode"),
        Type.atom("never_utf"),
      ]);

      assertCompileErrorTuple(
        result,
        "using UTF is disabled by the application",
        0,
      );
    });

    it("raises ArgumentError on non-iodata pattern", () => {
      assertBoxedError(
        () => compileWithOpts(Type.atom("abc"), []),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises ArgumentError on non-binary bitstring pattern", () => {
      assertBoxedError(
        () => compileWithOpts(Type.bitstring([1]), []),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises ArgumentError on code point above 255 in byte mode", () => {
      assertBoxedError(
        () => compileWithOpts(Type.list([Type.integer(256)]), []),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises ArgumentError on improper integer tail", () => {
      const pattern = Type.improperList([Type.integer(97), Type.integer(98)]);

      assertBoxedError(
        () => compileWithOpts(pattern, []),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises ArgumentError on non-binary bitstring pattern in unicode mode", () => {
      assertBoxedError(
        () => compileWithOpts(Type.bitstring([1]), [Type.atom("unicode")]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises plain ArgumentError on non-chardata pattern in unicode mode", () => {
      assertBoxedError(
        () => compileWithOpts(Type.atom("abc"), [Type.atom("unicode")]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on surrogate code point in unicode mode", () => {
      assertBoxedError(
        () =>
          compileWithOpts(Type.list([Type.integer(0xd800)]), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on code point above 0x10FFFF in unicode mode", () => {
      assertBoxedError(
        () =>
          compileWithOpts(Type.list([Type.integer(0x110000)]), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid UTF-8 binary inside list in unicode mode", () => {
      assertBoxedError(
        () =>
          compileWithOpts(Type.list([Bitstring.fromBytes([255])]), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on improper integer tail in unicode mode", () => {
      const pattern = Type.improperList([Type.integer(97), Type.integer(98)]);

      assertBoxedError(
        () => compileWithOpts(pattern, [Type.atom("unicode")]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError on invalid option", () => {
      assertBoxedError(
        () => compileWithOpts(Type.bitstring("ab"), [Type.atom("bad")]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid options"),
      );
    });

    it("raises ArgumentError on run-only option", () => {
      assertBoxedError(
        () => compileWithOpts(Type.bitstring("ab"), [Type.atom("notempty")]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid options"),
      );
    });

    it("raises ArgumentError on non-atom option", () => {
      assertBoxedError(
        () => compileWithOpts(Type.bitstring("ab"), [Type.integer(1)]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid options"),
      );
    });

    it("raises ArgumentError on invalid newline type", () => {
      assertBoxedError(
        () =>
          compileWithOpts(Type.bitstring("ab"), [
            Type.tuple([Type.atom("newline"), Type.atom("xx")]),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid options"),
      );
    });

    it("raises ArgumentError on non-list options", () => {
      assertBoxedError(
        () => compile(Type.bitstring("ab"), Type.atom("unicode")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid options"),
      );
    });

    it("raises ArgumentError on improper options list", () => {
      const options = Type.improperList([
        Type.atom("caseless"),
        Type.atom("foo"),
      ]);

      assertBoxedError(
        () => compile(Type.bitstring("ab"), options),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid options"),
      );
    });

    it("raises ArgumentError with both bullets on non-iodata pattern and invalid options", () => {
      assertBoxedError(
        () => compileWithOpts(Type.atom("abc"), [Type.atom("bad")]),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: not an iodata term\n  * 2nd argument: invalid options\n",
      );
    });
  });

  describe("import/1", () => {
    const importPattern = Erlang_Re["import/1"];

    // The client validates only the serialization magic bytes of the header
    // and code blobs, so synthetic blobs stand in for PCRE2-native ones.
    const header = Bitstring.fromBytes([
      ...[..."re-PCRE2"].map((char) => char.charCodeAt(0)),
      207,
      31,
      115,
      169,
      1,
      0,
    ]);

    const code = Bitstring.fromBytes([
      ...[..."S2RP"].map((char) => char.charCodeAt(0)),
      1,
      2,
      3,
    ]);

    const buildExported = (source, opts) =>
      Type.tuple([
        Type.atom("re_exported_pattern"),
        header,
        Type.bitstring(source),
        Type.list(opts),
        code,
      ]);

    it("imports an exported pattern", () => {
      const result = importPattern(
        buildExported("(a)b", [Type.atom("export"), Type.atom("caseless")]),
      );

      assertRePattern(result, 1, 0, 0);
    });

    it("sets the unicode flag from the exported options", () => {
      const result = importPattern(
        buildExported("(a)é", [Type.atom("export"), Type.atom("unicode")]),
      );

      assertRePattern(result, 1, 1, 0);
    });

    it("sets the use_crlf flag from the exported options", () => {
      const result = importPattern(
        buildExported("a", [
          Type.atom("export"),
          Type.tuple([Type.atom("newline"), Type.atom("crlf")]),
        ]),
      );

      assertRePattern(result, 0, 0, 1);
    });

    it("raises ArgumentError on non-tuple term", () => {
      assertBoxedError(
        () => importPattern(Type.atom("foo")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not an exported regular expression",
        ),
      );
    });

    it("raises ArgumentError on wrong tuple tag", () => {
      const exported = buildExported("ab", [Type.atom("export")]);
      exported.data[0] = Type.atom("bad");

      assertBoxedError(
        () => importPattern(exported),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not an exported regular expression",
        ),
      );
    });

    it("raises ArgumentError on wrong tuple size", () => {
      const exported = buildExported("ab", [Type.atom("export")]);
      const truncated = Type.tuple(exported.data.slice(0, 4));

      assertBoxedError(
        () => importPattern(truncated),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not an exported regular expression",
        ),
      );
    });

    it("raises ArgumentError on tampered header magic", () => {
      const exported = buildExported("ab", [Type.atom("export")]);
      exported.data[1] = Bitstring.fromBytes([
        ...[..."XX-PCRE2"].map((char) => char.charCodeAt(0)),
        0,
        0,
        0,
        0,
        0,
        0,
      ]);

      assertBoxedError(
        () => importPattern(exported),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not an exported regular expression",
        ),
      );
    });

    it("raises ArgumentError on truncated header", () => {
      const exported = buildExported("ab", [Type.atom("export")]);
      exported.data[1] = Type.bitstring("re-PCRE2");

      assertBoxedError(
        () => importPattern(exported),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not an exported regular expression",
        ),
      );
    });

    it("raises ArgumentError on tampered code blob", () => {
      const exported = buildExported("ab", [Type.atom("export")]);
      exported.data[4] = Bitstring.fromBytes([1, 2, 3]);

      assertBoxedError(
        () => importPattern(exported),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not an exported regular expression",
        ),
      );
    });
  });

  describe("version/0", () => {
    const version = Erlang_Re["version/0"];

    it("returns supported PCRE version", () => {
      const result = version();

      assert.equal(result.type, "bitstring");
      assert.match(result.text, /^\d+\.\d+ \d{4}-\d{2}-\d{2}$/);
    });
  });
});
