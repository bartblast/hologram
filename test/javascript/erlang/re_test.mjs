"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang from "../../../assets/js/erlang/erlang.mjs";
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
        Interpreter.buildMultiArgumentErrorMsg([
          [1, "not an iodata term"],
          [2, "invalid options"],
        ]),
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

  describe("inspect/2", () => {
    const compile = Erlang_Re["compile/2"];
    const inspect = Erlang_Re["inspect/2"];

    const compilePattern = (source, opts = []) => {
      const result = compile(Type.bitstring(source), Type.list(opts));
      return result.data[1];
    };

    it("returns an empty namelist without named groups", () => {
      const compiled = compilePattern("(a)(b)");

      assert.deepEqual(
        inspect(compiled, Type.atom("namelist")),
        Type.tuple([Type.atom("namelist"), Type.list([])]),
      );
    });

    it("returns group names sorted by byte order", () => {
      const compiled = compilePattern("(?<zz>a)(?<aa>b)(?<mm>c)");

      assert.deepEqual(
        inspect(compiled, Type.atom("namelist")),
        Type.tuple([
          Type.atom("namelist"),
          Type.list([
            Type.bitstring("aa"),
            Type.bitstring("mm"),
            Type.bitstring("zz"),
          ]),
        ]),
      );
    });

    it("deduplicates names with the dupnames option", () => {
      const compiled = compilePattern("(?<x>a)|(?<x>b)", [
        Type.atom("dupnames"),
      ]);

      assert.deepEqual(
        inspect(compiled, Type.atom("namelist")),
        Type.tuple([Type.atom("namelist"), Type.list([Type.bitstring("x")])]),
      );
    });

    it("returns unicode group names", () => {
      const compiled = compilePattern("(?<héé>a)", [Type.atom("unicode")]);

      assert.deepEqual(
        inspect(compiled, Type.atom("namelist")),
        Type.tuple([Type.atom("namelist"), Type.list([Type.bitstring("héé")])]),
      );
    });

    it("raises ArgumentError on non-tuple pattern", () => {
      assertBoxedError(
        () => inspect(Type.atom("foo"), Type.atom("namelist")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a compiled regular expression",
        ),
      );
    });

    it("raises ArgumentError on unknown pattern reference", () => {
      const rePattern = Type.tuple([
        Type.atom("re_pattern"),
        Type.integer(0),
        Type.integer(0),
        Type.integer(0),
        Erlang["make_ref/0"](),
      ]);

      assertBoxedError(
        () => inspect(rePattern, Type.atom("namelist")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a compiled regular expression",
        ),
      );
    });

    it("raises ArgumentError on invalid item", () => {
      const compiled = compilePattern("ab");

      assertBoxedError(
        () => inspect(compiled, Type.atom("foo")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a valid item"),
      );
    });

    it("raises ArgumentError on bad pattern before bad item", () => {
      assertBoxedError(
        () => inspect(Type.atom("foo"), Type.atom("bar")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a compiled regular expression",
        ),
      );
    });
  });

  describe("run/2", () => {
    it("matches with default options", () => {
      const result = Erlang_Re["run/2"](
        Type.bitstring("abbc"),
        Type.bitstring("b+"),
      );

      assert.deepEqual(
        result,
        Type.tuple([
          Type.atom("match"),
          Type.list([Type.tuple([Type.integer(1), Type.integer(2)])]),
        ]),
      );
    });

    it("returns nomatch without a match", () => {
      const result = Erlang_Re["run/2"](
        Type.bitstring("x"),
        Type.bitstring("b+"),
      );

      assert.deepEqual(result, Type.atom("nomatch"));
    });
  });

  describe("run/3", () => {
    const run = (subject, pattern, opts = []) =>
      Erlang_Re["run/3"](subject, pattern, Type.list(opts));

    const compilePattern = (source, opts = []) => {
      const result = Erlang_Re["compile/2"](
        Type.bitstring(source),
        Type.list(opts),
      );

      return result.data[1];
    };

    const assertMatchResult = (result, indexPairs) => {
      assert.deepEqual(
        result,
        Type.tuple([
          Type.atom("match"),
          Type.list(
            indexPairs.map(([start, length]) =>
              Type.tuple([Type.integer(start), Type.integer(length)]),
            ),
          ),
        ]),
      );
    };

    const assertGlobalMatchResult = (result, matchesIndexPairs) => {
      assert.deepEqual(
        result,
        Type.tuple([
          Type.atom("match"),
          Type.list(
            matchesIndexPairs.map((indexPairs) =>
              Type.list(
                indexPairs.map(([start, length]) =>
                  Type.tuple([Type.integer(start), Type.integer(length)]),
                ),
              ),
            ),
          ),
        ]),
      );
    };

    const captureOption = (valueSpec, type) =>
      type === undefined
        ? Type.tuple([Type.atom("capture"), valueSpec])
        : Type.tuple([Type.atom("capture"), valueSpec, Type.atom(type)]);

    const limitOption = (tag, limit) =>
      Type.tuple([Type.atom(tag), Type.integer(limit)]);

    const matchTuple = (values) =>
      Type.tuple([Type.atom("match"), Type.list(values)]);

    const offsetOption = (offset) =>
      Type.tuple([Type.atom("offset"), Type.integer(offset)]);

    it("matches with a raw binary pattern", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("b+"));

      assertMatchResult(result, [[1, 2]]);
    });

    it("matches with a raw charlist pattern", () => {
      const result = run(Type.bitstring("abbc"), Type.charlist("b+"));

      assertMatchResult(result, [[1, 2]]);
    });

    it("matches with a compiled pattern", () => {
      const result = run(Type.bitstring("abbc"), compilePattern("b+"));

      assertMatchResult(result, [[1, 2]]);
    });

    it("matches at the leftmost position", () => {
      const result = run(Type.bitstring("abbb"), Type.bitstring("b+"));

      assertMatchResult(result, [[1, 3]]);
    });

    it("matches on the interpreter route", () => {
      const result = run(Type.bitstring("abc"), Type.bitstring("b\\Kc"));

      assertMatchResult(result, [[2, 1]]);
    });

    it("matches an iodata subject", () => {
      const subject = Type.improperList([
        Type.bitstring("ab"),
        Type.bitstring("bc"),
      ]);

      const result = run(subject, Type.bitstring("b+"));

      assertMatchResult(result, [[1, 2]]);
    });

    it("matches an empty pattern on an empty subject", () => {
      const result = run(Type.bitstring(""), Type.bitstring(""));

      assertMatchResult(result, [[0, 0]]);
    });

    it("returns nomatch without a match", () => {
      const result = run(Type.bitstring("abc"), Type.bitstring("x"));

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("returns capture group index tuples", () => {
      const result = run(Type.bitstring("abc"), Type.bitstring("(a)(b)(c)"));

      assertMatchResult(result, [
        [0, 3],
        [0, 1],
        [1, 1],
        [2, 1],
      ]);
    });

    it("returns {-1, 0} for unset group before a set group", () => {
      const result = run(Type.bitstring("b"), Type.bitstring("(a)|(b)"));

      assertMatchResult(result, [
        [0, 1],
        [-1, 0],
        [0, 1],
      ]);
    });

    it("omits trailing unset groups", () => {
      const result = run(
        Type.bitstring("ab"),
        Type.bitstring("(a)(b)(x)?(y)?"),
      );

      assertMatchResult(result, [
        [0, 2],
        [0, 1],
        [1, 1],
      ]);
    });

    it("compiles a raw pattern with compile options", () => {
      const result = run(Type.bitstring("ABC"), Type.bitstring("abc"), [
        Type.atom("caseless"),
      ]);

      assertMatchResult(result, [[0, 3]]);
    });

    it("anchored option matches at the start", () => {
      const result = run(Type.bitstring("abc"), Type.bitstring("a"), [
        Type.atom("anchored"),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("anchored option pins the match to the start", () => {
      const result = run(Type.bitstring("abc"), Type.bitstring("b"), [
        Type.atom("anchored"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("anchored option works with a compiled pattern", () => {
      const result = run(Type.bitstring("abc"), compilePattern("b"), [
        Type.atom("anchored"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("compile-time anchored pattern matches at the start", () => {
      const compiled = compilePattern("b", [Type.atom("anchored")]);

      const result = run(Type.bitstring("bbc"), compiled);

      assertMatchResult(result, [[0, 1]]);
    });

    it("compile-time anchored pattern pins the match", () => {
      const compiled = compilePattern("b", [Type.atom("anchored")]);

      const result = run(Type.bitstring("abc"), compiled);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("returns byte offsets with the unicode option", () => {
      const result = run(Type.bitstring("éb"), Type.bitstring("b"), [
        Type.atom("unicode"),
      ]);

      assertMatchResult(result, [[2, 1]]);
    });

    it("decodes the subject with a unicode compiled pattern", () => {
      const compiled = compilePattern("é", [Type.atom("unicode")]);

      const result = run(Type.bitstring("aéb"), compiled);

      assertMatchResult(result, [[1, 2]]);
    });

    it("accepts unicode char data subject", () => {
      const subject = Type.list([Type.integer(233), Type.integer(98)]);

      const result = run(subject, Type.bitstring("b"), [Type.atom("unicode")]);

      assertMatchResult(result, [[2, 1]]);
    });

    it("defaults the capture type to index", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.atom("all")),
      ]);

      assertMatchResult(result, [
        [0, 3],
        [1, 2],
      ]);
    });

    it("captures all with the binary type", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.atom("all"), "binary"),
      ]);

      assert.deepEqual(
        result,
        matchTuple([
          Bitstring.fromBytes([97, 98, 98]),
          Bitstring.fromBytes([98, 98]),
        ]),
      );
    });

    it("captures all with the list type", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.atom("all"), "list"),
      ]);

      assert.deepEqual(
        result,
        matchTuple([Type.charlist("abb"), Type.charlist("bb")]),
      );
    });

    it("returns UTF-8 binaries with the binary type in unicode mode", () => {
      const result = run(Type.bitstring("aéb"), Type.bitstring("(éb)"), [
        Type.atom("unicode"),
        captureOption(Type.atom("all"), "binary"),
      ]);

      assert.deepEqual(
        result,
        matchTuple([Type.bitstring("éb"), Type.bitstring("éb")]),
      );
    });

    it("returns raw bytes with the binary type in byte mode", () => {
      const result = run(
        Bitstring.fromBytes([97, 233]),
        Bitstring.fromBytes([233]),
        [captureOption(Type.atom("all"), "binary")],
      );

      assert.deepEqual(result, matchTuple([Bitstring.fromBytes([233])]));
    });

    it("returns code points with the list type in unicode mode", () => {
      const result = run(Type.bitstring("a😀"), Type.bitstring("(😀)"), [
        Type.atom("unicode"),
        captureOption(Type.atom("all"), "list"),
      ]);

      assert.deepEqual(
        result,
        matchTuple([
          Type.list([Type.integer(128_512)]),
          Type.list([Type.integer(128_512)]),
        ]),
      );
    });

    it("returns bytes with the list type in byte mode", () => {
      const result = run(
        Bitstring.fromBytes([97, 233]),
        Bitstring.fromBytes([233]),
        [captureOption(Type.atom("all"), "list")],
      );

      assert.deepEqual(result, matchTuple([Type.list([Type.integer(233)])]));
    });

    it("captures only the full match with the first spec", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.atom("first")),
      ]);

      assertMatchResult(result, [[0, 3]]);
    });

    it("captures the full match binary with the first spec", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.atom("first"), "binary"),
      ]);

      assert.deepEqual(result, matchTuple([Bitstring.fromBytes([97, 98, 98])]));
    });

    it("returns bare match with the none spec", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.atom("none")),
      ]);

      assert.deepEqual(result, Type.atom("match"));
    });

    it("returns bare match with the none spec and a type", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.atom("none"), "binary"),
      ]);

      assert.deepEqual(result, Type.atom("match"));
    });

    it("captures only groups with the all_but_first spec", () => {
      const result = run(Type.bitstring("abc"), Type.bitstring("a(b)(c)"), [
        captureOption(Type.atom("all_but_first")),
      ]);

      assertMatchResult(result, [
        [1, 1],
        [2, 1],
      ]);
    });

    it("returns empty list with the all_but_first spec and no groups", () => {
      const result = run(Type.bitstring("abc"), Type.bitstring("b"), [
        captureOption(Type.atom("all_but_first")),
      ]);

      assert.deepEqual(result, matchTuple([]));
    });

    it("truncates trailing unset groups with the all_but_first spec", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("(a)(b)?(c)?"), [
        captureOption(Type.atom("all_but_first")),
      ]);

      assertMatchResult(result, [
        [0, 1],
        [1, 1],
      ]);
    });

    it("sorts names by byte order with the all_names spec", () => {
      const result = run(
        Type.bitstring("xy"),
        Type.bitstring("(?<b>x)(?<a>y)"),
        [captureOption(Type.atom("all_names"))],
      );

      assertMatchResult(result, [
        [1, 1],
        [0, 1],
      ]);
    });

    it("keeps trailing unset names with the all_names spec", () => {
      const result = run(
        Type.bitstring("x"),
        Type.bitstring("(?<a>x)(?<b>z)?"),
        [captureOption(Type.atom("all_names"))],
      );

      assertMatchResult(result, [
        [0, 1],
        [-1, 0],
      ]);
    });

    it("returns bare match with the all_names spec and no named groups", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("a(b)"), [
        captureOption(Type.atom("all_names")),
      ]);

      assert.deepEqual(result, Type.atom("match"));
    });

    it("collapses duplicate names to the first set group with the all_names spec", () => {
      const result = run(
        Type.bitstring("b"),
        Type.bitstring("(?<n>a)?(?<n>b)?"),
        [Type.atom("dupnames"), captureOption(Type.atom("all_names"))],
      );

      assertMatchResult(result, [[0, 1]]);
    });

    it("captures listed group indices in the given order", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("(a)(b)"), [
        captureOption(Type.list([Type.integer(2), Type.integer(0)])),
      ]);

      assertMatchResult(result, [
        [1, 1],
        [0, 2],
      ]);
    });

    it("treats an out-of-range group index as unset", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("(a)"), [
        captureOption(Type.list([Type.integer(5)])),
      ]);

      assertMatchResult(result, [[-1, 0]]);
    });

    it("treats the maximum group index as unset", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("(a)"), [
        captureOption(Type.list([Type.integer(2_147_483_647)])),
      ]);

      assertMatchResult(result, [[-1, 0]]);
    });

    it("resolves an atom group name", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("(?<foo>b+)"), [
        captureOption(Type.list([Type.atom("foo")])),
      ]);

      assertMatchResult(result, [[1, 2]]);
    });

    it("resolves a binary group name", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("(?<foo>b+)"), [
        captureOption(Type.list([Type.bitstring("foo")])),
      ]);

      assertMatchResult(result, [[1, 2]]);
    });

    it("resolves a charlist group name", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("(?<foo>b+)"), [
        captureOption(Type.list([Type.charlist("foo")])),
      ]);

      assertMatchResult(result, [[1, 2]]);
    });

    it("resolves a nested chardata group name", () => {
      const name = Type.list([
        Type.bitstring("f"),
        Type.list([Type.integer(111), Type.bitstring("o")]),
      ]);

      const result = run(Type.bitstring("abbc"), Type.bitstring("(?<foo>b+)"), [
        captureOption(Type.list([name])),
      ]);

      assertMatchResult(result, [[1, 2]]);
    });

    it("treats an unknown group name as unset", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("(?<foo>b+)"), [
        captureOption(Type.list([Type.atom("bar")]), "binary"),
      ]);

      assert.deepEqual(result, matchTuple([Type.bitstring("")]));
    });

    it("treats an invalid UTF-8 binary name as unset", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("(?<foo>b+)"), [
        captureOption(Type.list([Bitstring.fromBytes([255])]), "binary"),
      ]);

      assert.deepEqual(result, matchTuple([Type.bitstring("")]));
    });

    it("resolves a duplicate name to the first set group", () => {
      const result = run(
        Type.bitstring("b"),
        Type.bitstring("(?<n>a)?(?<n>b)?"),
        [Type.atom("dupnames"), captureOption(Type.list([Type.atom("n")]))],
      );

      assertMatchResult(result, [[0, 1]]);
    });

    it("returns bare match with an empty capture list", () => {
      const result = run(Type.bitstring("abbc"), Type.bitstring("a(b+)"), [
        captureOption(Type.list()),
      ]);

      assert.deepEqual(result, Type.atom("match"));
    });

    it("keeps trailing unset groups with a capture list", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("(a)(b)?"), [
        captureOption(Type.list([Type.integer(1), Type.integer(2)])),
      ]);

      assertMatchResult(result, [
        [0, 1],
        [-1, 0],
      ]);
    });

    it("returns nomatch with a capture spec", () => {
      const result = run(Type.bitstring("z"), Type.bitstring("a"), [
        captureOption(Type.atom("first"), "binary"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("uses the last capture option", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("a"), [
        captureOption(Type.atom("none")),
        captureOption(Type.atom("first")),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("applies the capture spec to a compiled pattern", () => {
      const result = run(Type.bitstring("abbc"), compilePattern("a(b+)"), [
        captureOption(Type.atom("all_but_first"), "binary"),
      ]);

      assert.deepEqual(result, matchTuple([Bitstring.fromBytes([98, 98])]));
    });

    it("starts matching at the offset", () => {
      const result = run(Type.bitstring("abab"), Type.bitstring("ab"), [
        offsetOption(1),
      ]);

      assertMatchResult(result, [[2, 2]]);
    });

    it("matches an empty pattern at the end offset", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring(""), [
        offsetOption(2),
      ]);

      assertMatchResult(result, [[2, 0]]);
    });

    it("uses the last offset option", () => {
      const result = run(Type.bitstring("aba"), Type.bitstring("a"), [
        offsetOption(1),
        offsetOption(0),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("^ doesn't match at the offset", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("^b"), [
        offsetOption(1),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("^ matches after a newline before the offset with multiline", () => {
      const result = run(Type.bitstring("ab\ncd"), Type.bitstring("^c"), [
        offsetOption(3),
        Type.atom("multiline"),
      ]);

      assertMatchResult(result, [[3, 1]]);
    });

    it("\\A doesn't match at the offset", () => {
      const result = run(Type.bitstring("aa"), Type.bitstring("\\Aa"), [
        offsetOption(1),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("\\G matches at the offset", () => {
      const result = run(Type.bitstring("aba"), Type.bitstring("\\Ga"), [
        offsetOption(2),
      ]);

      assertMatchResult(result, [[2, 1]]);
    });

    it("a lookbehind sees before the offset", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("(?<=a)b"), [
        offsetOption(1),
      ]);

      assertMatchResult(result, [[1, 1]]);
    });

    it("offset counts bytes in unicode mode", () => {
      const result = run(Type.bitstring("éb"), Type.bitstring("b"), [
        Type.atom("unicode"),
        offsetOption(2),
      ]);

      assertMatchResult(result, [[2, 1]]);
    });

    it("anchored pins the match to the offset", () => {
      const result = run(Type.bitstring("abb"), Type.bitstring("b"), [
        Type.atom("anchored"),
        offsetOption(1),
      ]);

      assertMatchResult(result, [[1, 1]]);
    });

    it("notbol makes ^ fail at the subject start", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("^a"), [
        Type.atom("notbol"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("notbol keeps ^ matching after an internal newline", () => {
      const result = run(Type.bitstring("a\nb"), Type.bitstring("^b"), [
        Type.atom("multiline"),
        Type.atom("notbol"),
      ]);

      assertMatchResult(result, [[2, 1]]);
    });

    it("notbol doesn't affect \\A", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("\\Aa"), [
        Type.atom("notbol"),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("notbol works with a compiled pattern", () => {
      const result = run(Type.bitstring("ab"), compilePattern("^a"), [
        Type.atom("notbol"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("noteol makes $ fail at the subject end", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("b$"), [
        Type.atom("noteol"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("noteol makes $ fail before a final newline", () => {
      const result = run(Type.bitstring("ab\n"), Type.bitstring("b$"), [
        Type.atom("noteol"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("noteol keeps $ matching before an internal newline", () => {
      const result = run(Type.bitstring("a\nb"), Type.bitstring("a$"), [
        Type.atom("multiline"),
        Type.atom("noteol"),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("noteol doesn't affect \\z", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("b\\z"), [
        Type.atom("noteol"),
      ]);

      assertMatchResult(result, [[1, 1]]);
    });

    it("notempty backtracks to a non-empty match", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("|a"), [
        Type.atom("notempty"),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("notempty rejects empty matches at every position", () => {
      const result = run(Type.bitstring("b"), Type.bitstring("a*"), [
        Type.atom("notempty"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("notempty scans past rejected empty matches", () => {
      const result = run(Type.bitstring("ba"), Type.bitstring("a*"), [
        Type.atom("notempty"),
      ]);

      assertMatchResult(result, [[1, 1]]);
    });

    it("notempty_atstart rejects an empty match at the start position", () => {
      const result = run(Type.bitstring("ba"), Type.bitstring("a*"), [
        Type.atom("notempty_atstart"),
      ]);

      assertMatchResult(result, [[1, 1]]);
    });

    it("notempty_atstart allows an empty match past the offset", () => {
      const result = run(Type.bitstring("ba"), Type.bitstring("b*"), [
        Type.atom("notempty_atstart"),
        offsetOption(1),
      ]);

      assertMatchResult(result, [[2, 0]]);
    });

    it("firstline rejects a match past the first newline", () => {
      const result = run(Type.bitstring("a\nb"), Type.bitstring("b"), [
        Type.atom("firstline"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("firstline allows a match before the first newline", () => {
      const result = run(Type.bitstring("ab\ncd"), Type.bitstring("b"), [
        Type.atom("firstline"),
      ]);

      assertMatchResult(result, [[1, 1]]);
    });

    it("firstline allows a match crossing the first newline", () => {
      const result = run(Type.bitstring("ab\ncd"), Type.bitstring("b\\nc"), [
        Type.atom("firstline"),
      ]);

      assertMatchResult(result, [[1, 3]]);
    });

    it("firstline uses the newline convention", () => {
      const result = run(Type.bitstring("a\rb"), Type.bitstring("b"), [
        Type.atom("firstline"),
        Type.tuple([Type.atom("newline"), Type.atom("anycrlf")]),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("firstline counts newlines from the offset", () => {
      const result = run(Type.bitstring("a\nb"), Type.bitstring("b"), [
        Type.atom("firstline"),
        offsetOption(2),
      ]);

      assertMatchResult(result, [[2, 1]]);
    });

    it("compile-time firstline pattern applies when running", () => {
      const compiled = compilePattern("b", [Type.atom("firstline")]);

      const result = run(Type.bitstring("a\nb"), compiled, []);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("global collects successive matches", () => {
      const result = run(Type.bitstring("abab"), Type.bitstring("a"), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[0, 1]], [[2, 1]]]);
    });

    it("global collects captures per match", () => {
      const result = run(Type.bitstring("abab"), Type.bitstring("a(b)"), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [
        [
          [0, 2],
          [1, 1],
        ],
        [
          [2, 2],
          [3, 1],
        ],
      ]);
    });

    it("global truncates trailing unset groups per match", () => {
      const result = run(Type.bitstring("aba"), Type.bitstring("a(b)?"), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [
        [
          [0, 2],
          [1, 1],
        ],
        [[2, 1]],
      ]);
    });

    it("global advances past an empty match", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("a*"), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[0, 1]], [[1, 0]], [[2, 0]]]);
    });

    it("global reports a successful anchored retry after an empty match", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("|a"), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[0, 0]], [[0, 1]], [[1, 0]]]);
    });

    it("global matches once on an empty subject", () => {
      const result = run(Type.bitstring(""), Type.bitstring(""), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[0, 0]]]);
    });

    it("global continues at the previous match end", () => {
      const result = run(Type.bitstring("abab"), Type.bitstring("a\\Kb"), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[1, 1]], [[3, 1]]]);
    });

    it("global advances over a CRLF pair as one newline", () => {
      const result = run(Type.bitstring("\r\n"), Type.bitstring(""), [
        Type.atom("global"),
        Type.tuple([Type.atom("newline"), Type.atom("crlf")]),
      ]);

      assertGlobalMatchResult(result, [[[0, 0]], [[2, 0]]]);
    });

    it("global advances over a whole character in unicode mode", () => {
      const result = run(Type.bitstring("😀"), Type.bitstring("x*"), [
        Type.atom("global"),
        Type.atom("unicode"),
      ]);

      assertGlobalMatchResult(result, [[[0, 0]], [[4, 0]]]);
    });

    it("global starts at the offset", () => {
      const result = run(Type.bitstring("abab"), Type.bitstring("a"), [
        Type.atom("global"),
        offsetOption(1),
      ]);

      assertGlobalMatchResult(result, [[[2, 1]]]);
    });

    it("global returns nomatch on offset beyond the subject", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("a"), [
        Type.atom("global"),
        offsetOption(5),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("global returns nomatch on unicode offset beyond the subject", () => {
      const result = run(Type.bitstring("éb"), Type.bitstring("b"), [
        Type.atom("global"),
        Type.atom("unicode"),
        offsetOption(9),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("global anchored continues while matches are adjacent", () => {
      const result = run(Type.bitstring("aab"), Type.bitstring("a"), [
        Type.atom("anchored"),
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[0, 1]], [[1, 1]]]);
    });

    it("global anchored stops at the first failed position", () => {
      const result = run(Type.bitstring("aba"), Type.bitstring("a"), [
        Type.atom("anchored"),
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[0, 1]]]);
    });

    it("global applies scan flags to every attempt", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("a*"), [
        Type.atom("global"),
        Type.atom("notempty"),
      ]);

      assertGlobalMatchResult(result, [[[0, 1]]]);
    });

    it("global returns nomatch without a match", () => {
      const result = run(Type.bitstring("ab"), Type.bitstring("x"), [
        Type.atom("global"),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("global shapes binary captures per match", () => {
      const result = run(Type.bitstring("abab"), Type.bitstring("a(b)"), [
        Type.atom("global"),
        captureOption(Type.atom("all_but_first"), "binary"),
      ]);

      assert.deepEqual(
        result,
        matchTuple([
          Type.list([Bitstring.fromBytes([98])]),
          Type.list([Bitstring.fromBytes([98])]),
        ]),
      );
    });

    it("global returns bare match with the none spec", () => {
      const result = run(Type.bitstring("aa"), Type.bitstring("a"), [
        Type.atom("global"),
        captureOption(Type.atom("none")),
      ]);

      assert.deepEqual(result, Type.atom("match"));
    });

    it("global works with a compiled pattern", () => {
      const result = run(Type.bitstring("aba"), compilePattern("a"), [
        Type.atom("global"),
      ]);

      assertGlobalMatchResult(result, [[[0, 1]], [[2, 1]]]);
    });

    it("an exceeded match limit reports nomatch", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("a"), [
        limitOption("match_limit", 0),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("matches within the match limit", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("a"), [
        limitOption("match_limit", 100),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("the match limit stops runaway backtracking", () => {
      const result = run(
        Type.bitstring("aaaaaaaaaax"),
        Type.bitstring("(a+)+b"),
        [limitOption("match_limit", 1)],
      );

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("an exceeded recursion limit reports nomatch", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("a"), [
        limitOption("match_limit_recursion", 0),
      ]);

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("matches within the recursion limit", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("a"), [
        limitOption("match_limit_recursion", 100),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("match limit works with a compiled pattern", () => {
      const result = run(
        Type.bitstring("aaaaaaaaaax"),
        compilePattern("(a+)+b"),
        [limitOption("match_limit", 1)],
      );

      assert.deepEqual(result, Type.atom("nomatch"));
    });

    it("uses the last match limit option", () => {
      const result = run(Type.bitstring("a"), Type.bitstring("a"), [
        limitOption("match_limit", 0),
        limitOption("match_limit", 100),
      ]);

      assertMatchResult(result, [[0, 1]]);
    });

    it("raises ArgumentError on non-iodata subject", () => {
      assertBoxedError(
        () => run(Type.atom("abc"), Type.bitstring("a")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises ArgumentError on non-binary bitstring subject", () => {
      assertBoxedError(
        () => run(Type.bitstring([1]), Type.bitstring("a")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises ArgumentError on subject code point above 255 in byte mode", () => {
      assertBoxedError(
        () => run(Type.list([Type.integer(256)]), Type.bitstring("a")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("raises ArgumentError on non-iodata pattern", () => {
      assertBoxedError(
        () => run(Type.bitstring("x"), Type.atom("foo")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "neither an iodata term nor a compiled regular expression",
        ),
      );
    });

    it("raises ArgumentError on non-binary bitstring pattern", () => {
      assertBoxedError(
        () => run(Type.bitstring("x"), Type.bitstring([1])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "neither an iodata term nor a compiled regular expression",
        ),
      );
    });

    it("raises ArgumentError on pattern code point above 255 in byte mode", () => {
      assertBoxedError(
        () => run(Type.bitstring("x"), Type.list([Type.integer(256)])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "neither an iodata term nor a compiled regular expression",
        ),
      );
    });

    it("raises ArgumentError on unknown compiled pattern reference", () => {
      const rePattern = Type.tuple([
        Type.atom("re_pattern"),
        Type.integer(0),
        Type.integer(0),
        Type.integer(0),
        Erlang["make_ref/0"](),
      ]);

      assertBoxedError(
        () => run(Type.bitstring("x"), rePattern),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "neither an iodata term nor a compiled regular expression",
        ),
      );
    });

    it("raises ArgumentError on non-chardata pattern with the unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.atom("foo"), [Type.atom("unicode")]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "neither an iodata term nor a compiled regular expression",
        ),
      );
    });

    it("raises ArgumentError on invalid raw pattern", () => {
      assertBoxedError(
        () => run(Type.bitstring("abc"), Type.bitstring("a{2,1}")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "could not parse regular expression\nnumbers out of order in {} quantifier on character 5",
        ),
      );
    });

    it("raises ArgumentError with byte error position in unicode mode", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.bitstring("é("), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "could not parse regular expression\nmissing closing parenthesis on character 3",
        ),
      );
    });

    it("raises ArgumentError on invalid UTF-8 after a UTF pattern verb", () => {
      const pattern = Type.improperList([
        Type.bitstring("(*UTF)"),
        Bitstring.fromBytes([255]),
      ]);

      assertBoxedError(
        () => run(Type.bitstring("x"), pattern),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "could not parse regular expression\nUTF-8 error: illegal byte (0xfe or 0xff) on character 6",
        ),
      );
    });

    it("raises ArgumentError on invalid option", () => {
      assertBoxedError(
        () => run(Type.bitstring("x"), Type.bitstring("a"), [Type.atom("bad")]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on non-list options", () => {
      assertBoxedError(
        () =>
          Erlang_Re["run/3"](
            Type.bitstring("x"),
            Type.bitstring("a"),
            Type.atom("bad"),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on improper options list", () => {
      const options = Type.improperList([
        Type.atom("anchored"),
        Type.atom("bad"),
      ]);

      assertBoxedError(
        () =>
          Erlang_Re["run/3"](Type.bitstring("x"), Type.bitstring("a"), options),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("combines subject and pattern errors", () => {
      assertBoxedError(
        () => run(Type.atom("a"), Type.atom("b")),
        "ArgumentError",
        Interpreter.buildMultiArgumentErrorMsg([
          [1, "not an iodata term"],
          [2, "neither an iodata term nor a compiled regular expression"],
        ]),
      );
    });

    it("combines pattern and options errors", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.bitstring("a{2,1}"), [
            Type.atom("bad"),
          ]),
        "ArgumentError",
        Interpreter.buildMultiArgumentErrorMsg([
          [
            2,
            "could not parse regular expression\nnumbers out of order in {} quantifier on character 5",
          ],
          [3, "invalid options"],
        ]),
      );
    });

    it("combines subject and options errors", () => {
      assertBoxedError(
        () => run(Type.atom("a"), Type.bitstring("ok"), [Type.atom("bad")]),
        "ArgumentError",
        Interpreter.buildMultiArgumentErrorMsg([
          [1, "not an iodata term"],
          [3, "invalid options"],
        ]),
      );
    });

    it("combines subject, pattern and options errors", () => {
      assertBoxedError(
        () => run(Type.atom("a"), Type.atom("b"), [Type.atom("bad")]),
        "ArgumentError",
        Interpreter.buildMultiArgumentErrorMsg([
          [1, "not an iodata term"],
          [2, "neither an iodata term nor a compiled regular expression"],
          [3, "invalid options"],
        ]),
      );
    });

    it("combines pattern shape and options errors with the unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.atom("foo"), [
            Type.atom("unicode"),
            Type.atom("bad"),
          ]),
        "ArgumentError",
        Interpreter.buildMultiArgumentErrorMsg([
          [2, "neither an iodata term nor a compiled regular expression"],
          [3, "invalid options"],
        ]),
      );
    });

    it("subject error wins over compile option error with a compiled pattern", () => {
      assertBoxedError(
        () =>
          run(Type.atom("abc"), compilePattern("b"), [Type.atom("caseless")]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("options error wins over unicode conversion errors", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Bitstring.fromBytes([255]), [
            Type.atom("unicode"),
            Type.atom("bad"),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises plain ArgumentError on compile option with a compiled pattern", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), compilePattern("b"), [
            Type.atom("caseless"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on unicode option with a compiled pattern", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), compilePattern("b"), [Type.atom("unicode")]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid UTF-8 pattern with the unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Bitstring.fromBytes([255]), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid pattern char data with the unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.list([Type.atom("bad")]), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on surrogate pattern code point with the unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.list([Type.integer(0xd800)]), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on never_utf and unicode option clash", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.bitstring("a"), [
            Type.atom("unicode"),
            Type.atom("never_utf"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on UTF pattern verb with never_utf option", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.bitstring("(*UTF)a"), [
            Type.atom("never_utf"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on bad subject with parse error and unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.atom("abc"), Type.bitstring("a{2,1}"), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on non-chardata subject with the unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.atom("abc"), Type.bitstring("a"), [Type.atom("unicode")]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on surrogate subject code point with the unicode option", () => {
      assertBoxedError(
        () =>
          run(Type.list([Type.integer(0xd800)]), Type.bitstring("a"), [
            Type.atom("unicode"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid UTF-8 subject with a unicode compiled pattern", () => {
      const compiled = compilePattern("é", [Type.atom("unicode")]);

      const subject = Bitstring.fromBytes([255, 97, 98]);

      assertBoxedError(
        () => run(subject, compiled),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on non-iodata subject with a unicode compiled pattern", () => {
      const compiled = compilePattern("é", [Type.atom("unicode")]);

      assertBoxedError(
        () => run(Type.atom("abc"), compiled),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid UTF-8 subject with a UTF verb pattern", () => {
      assertBoxedError(
        () => run(Bitstring.fromBytes([255]), Type.bitstring("(*UTF)é")),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid capture spec atom", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.atom("bogus")),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on non-list capture spec", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.integer(1)),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on improper capture spec list", () => {
      const valueSpec = Type.improperList([Type.integer(0), Type.integer(1)]);

      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(valueSpec),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid capture type", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.atom("all"), "bogus"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on non-atom capture type", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            Type.tuple([
              Type.atom("capture"),
              Type.atom("all"),
              Type.integer(5),
            ]),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid capture type with the none spec", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.atom("none"), "bogus"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on negative group index", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.list([Type.integer(-1)])),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on group index above the 32-bit range", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.list([Type.integer(2_147_483_648n)])),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on float capture spec element", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.list([Type.float(1.5)])),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on non-binary bitstring capture spec element", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.list([Type.bitstring([1])])),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid code point in a name", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.list([Type.list([Type.integer(99_999_999)])])),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on improper name charlist", () => {
      const name = Type.improperList([Type.integer(102), Type.integer(111)]);

      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            captureOption(Type.list([name])),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on invalid capture spec without a match", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("z"), Type.bitstring("a"), [
            captureOption(Type.atom("bogus")),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError on capture option with extra elements", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            Type.tuple([
              Type.atom("capture"),
              Type.atom("all"),
              Type.atom("index"),
              Type.atom("extra"),
            ]),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("subject error wins over capture spec error", () => {
      assertBoxedError(
        () =>
          run(Type.atom("x"), Type.bitstring("a"), [
            captureOption(Type.atom("bogus")),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
      );
    });

    it("unicode pattern error wins over capture spec error", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("x"), Type.bitstring("("), [
            Type.atom("unicode"),
            captureOption(Type.atom("bogus")),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "could not parse regular expression\nmissing closing parenthesis on character 1",
        ),
      );
    });

    it("raises ArgumentError on negative offset", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("ab"), Type.bitstring("a"), [offsetOption(-1)]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on non-integer offset", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("ab"), Type.bitstring("a"), [
            Type.tuple([Type.atom("offset"), Type.atom("x")]),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on offset above the 32-bit range", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("ab"), Type.bitstring("a"), [
            offsetOption(2_147_483_648n),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on offset tuple with extra elements", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("ab"), Type.bitstring("a"), [
            Type.tuple([Type.atom("offset"), Type.integer(1), Type.integer(2)]),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises plain ArgumentError on offset beyond the subject", () => {
      assertBoxedError(
        () => run(Type.bitstring("ab"), Type.bitstring("a"), [offsetOption(3)]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on maximum offset beyond the subject", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("ab"), Type.bitstring("a"), [
            offsetOption(2_147_483_647),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on offset inside a character", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("éb"), Type.bitstring("b"), [
            Type.atom("unicode"),
            offsetOption(1),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on firstline with a compiled pattern", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a\nb"), compilePattern("b"), [
            Type.atom("firstline"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on offset inside a character with global", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("éb"), Type.bitstring("b"), [
            Type.atom("global"),
            Type.atom("unicode"),
            offsetOption(1),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("capture spec error wins over global nomatch", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("ab"), Type.bitstring("a"), [
            Type.atom("global"),
            offsetOption(5),
            captureOption(Type.atom("bogus")),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError on negative match limit", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            limitOption("match_limit", -1),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on non-integer match limit", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            Type.tuple([Type.atom("match_limit"), Type.atom("x")]),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on match limit above the 32-bit range", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            limitOption("match_limit_recursion", 2_147_483_648n),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises ArgumentError on match limit tuple with extra elements", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), Type.bitstring("a"), [
            Type.tuple([
              Type.atom("match_limit"),
              Type.integer(1),
              Type.integer(2),
            ]),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    });

    it("raises plain ArgumentError on newline option with a compiled pattern", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a\rb"), compilePattern("a.b"), [
            Type.tuple([Type.atom("newline"), Type.atom("cr")]),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises plain ArgumentError on bsr option with a compiled pattern", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a\vb"), compilePattern("a\\Rb"), [
            Type.atom("bsr_anycrlf"),
          ]),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError on invalid newline type with a compiled pattern", () => {
      assertBoxedError(
        () =>
          run(Type.bitstring("a"), compilePattern("a"), [
            Type.tuple([Type.atom("newline"), Type.atom("bogus")]),
          ]),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
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
