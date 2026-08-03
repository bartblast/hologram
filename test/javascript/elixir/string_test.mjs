import {
  assert,
  assertBoxedError,
  buildArgumentErrorMsg,
  buildFunctionClauseErrorMsg,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Elixir_String from "../../../assets/js/elixir/string.mjs";
import Type from "../../../assets/js/type.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";

defineRuntimeGlobals();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/string_test.exs
// Always update both together.

describe("Elixir_String", () => {
  describe("contains?/2", () => {
    const contains = Elixir_String["contains?/2"];

    describe("with a single pattern", () => {
      it("returns true when pattern is found", () => {
        const subject = Type.bitstring("hello world");
        const pattern = Type.bitstring("world");

        const result = contains(subject, pattern);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });

      it("returns false when pattern is not found", () => {
        const subject = Type.bitstring("hello world");
        const pattern = Type.bitstring("xyz");

        const result = contains(subject, pattern);
        const expected = Type.boolean(false);

        assert.deepStrictEqual(result, expected);
      });

      it("returns true when subject is non-empty and pattern is empty", () => {
        const subject = Type.bitstring("hello");
        const pattern = Type.bitstring("");

        const result = contains(subject, pattern);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });

      it("returns true when subject is empty and pattern is empty", () => {
        const subject = Type.bitstring("");
        const pattern = Type.bitstring("");

        const result = contains(subject, pattern);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });

      it("returns false when subject is empty and pattern is non-empty", () => {
        const subject = Type.bitstring("");
        const pattern = Type.bitstring("test");

        const result = contains(subject, pattern);
        const expected = Type.boolean(false);

        assert.deepStrictEqual(result, expected);
      });

      it("works with Unicode text", () => {
        const subject = Type.bitstring("全息图测试");
        const pattern = Type.bitstring("息图");

        const result = contains(subject, pattern);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });

      it("is case sensitive", () => {
        const subject = Type.bitstring("Hello World");
        const pattern = Type.bitstring("hello");

        const result = contains(subject, pattern);
        const expected = Type.boolean(false);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("with multiple patterns", () => {
      it("returns true when first pattern is found", () => {
        const subject = Type.bitstring("hello world");

        const patterns = Type.list([
          Type.bitstring("world"),
          Type.bitstring("xyz"),
          Type.bitstring("abc"),
        ]);

        const result = contains(subject, patterns);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });

      it("returns true when non-first pattern is found", () => {
        const subject = Type.bitstring("hello world");

        const patterns = Type.list([
          Type.bitstring("xyz"),
          Type.bitstring("world"),
          Type.bitstring("abc"),
        ]);

        const result = contains(subject, patterns);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });

      it("returns true when multiple patterns are found", () => {
        const subject = Type.bitstring("hello world");

        const patterns = Type.list([
          Type.bitstring("hello"),
          Type.bitstring("world"),
        ]);

        const result = contains(subject, patterns);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });

      it("returns false when no patterns are found", () => {
        const subject = Type.bitstring("hello world");

        const patterns = Type.list([
          Type.bitstring("xyz"),
          Type.bitstring("abc"),
          Type.bitstring("def"),
        ]);

        const result = contains(subject, patterns);
        const expected = Type.boolean(false);

        assert.deepStrictEqual(result, expected);
      });

      it("returns false when pattern list is empty", () => {
        const subject = Type.bitstring("hello world");
        const patterns = Type.list([]);

        const result = contains(subject, patterns);
        const expected = Type.boolean(false);

        assert.deepStrictEqual(result, expected);
      });

      it("works with Unicode patterns", () => {
        const subject = Type.bitstring("全息图测试");

        const patterns = Type.list([
          Type.bitstring("ąćł"),
          Type.bitstring("测试"),
        ]);

        const result = contains(subject, patterns);
        const expected = Type.boolean(true);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("error cases", () => {
      // The attempted function clauses come from the clause heads the runtime script
      // registers at bundle load, which unit tests don't run, so this twin asserts
      // the message without them.
      it("raises FunctionClauseError when subject is not a bitstring", () => {
        const subject = Type.atom("hello");
        const pattern = Type.bitstring("test");

        assertBoxedError(
          () => contains(subject, pattern),
          "FunctionClauseError",
          buildFunctionClauseErrorMsg("String.contains?/2", [subject, pattern]),
        );
      });

      // The attempted function clauses come from the clause heads the runtime script
      // registers at bundle load, which unit tests don't run, so this twin asserts
      // the message without them.
      it("raises FunctionClauseError when subject is a non-binary bitstring", () => {
        const subject = Type.bitstring([1, 0, 1, 0]);
        const pattern = Type.bitstring("test");

        assertBoxedError(
          () => contains(subject, pattern),
          "FunctionClauseError",
          buildFunctionClauseErrorMsg("String.contains?/2", [subject, pattern]),
        );
      });

      it("raises ArgumentError when pattern is invalid type", () => {
        const subject = Type.bitstring("hello world");
        const pattern = Type.integer(123);

        assertBoxedError(
          () => contains(subject, pattern),
          "ArgumentError",
          buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is a non-binary bitstring", () => {
        const subject = Type.bitstring("hello world");
        const pattern = Type.bitstring([1, 0, 1, 0]);

        assertBoxedError(
          () => contains(subject, pattern),
          "ArgumentError",
          buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern list contains non-bitstring pattern", () => {
        const subject = Type.bitstring("hello world");

        const patterns = Type.list([
          Type.bitstring("hello"),
          Type.atom("world"),
        ]);

        assertBoxedError(
          () => contains(subject, patterns),
          "ArgumentError",
          buildArgumentErrorMsg(1, "not a bitstring"),
        );
      });

      it("raises ArgumentError when pattern list contains non-binary bitstring pattern", () => {
        const subject = Type.bitstring("hello world");

        const patterns = Type.list([
          Type.bitstring("hello"),
          Type.bitstring([1, 0, 1, 0]),
        ]);

        assertBoxedError(
          () => contains(subject, patterns),
          "ArgumentError",
          buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises HologramInterpreterError for compiled patterns", () => {
        const subject = Type.bitstring("hello world");

        const compiledPattern = Type.tuple([
          Type.atom("bm"),
          Type.reference("my_node", [0, 1, 2, 3]),
        ]);

        assert.throw(
          () => contains(subject, compiledPattern),
          HologramInterpreterError,
          "String.contains?/2 with compiled patterns is not yet implemented in Hologram",
        );
      });
    });

    it("error frame carries args", () => {
      let caught;

      try {
        Elixir_String["contains?/2"](Type.atom("abc"), Type.bitstring("a"));
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "String",
          function: "contains?",
          arityOrArgs: Type.list([Type.atom("abc"), Type.bitstring("a")]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });

    it("error frame carries args and error_info for a non-bitstring pattern element", () => {
      let caught;

      try {
        Elixir_String["contains?/2"](
          Type.bitstring("abc"),
          Type.list([Type.integer(1)]),
        );
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "erlang",
          function: "byte_size",
          arityOrArgs: Type.list([Type.integer(1)]),
          file: null,
          line: null,
          errorInfo: Type.map([
            [Type.atom("module"), Type.atom("erl_erts_errors")],
          ]),
        },
      ]);
    });

    it("error frame carries args and error_info for an invalid pattern type", () => {
      let caught;

      try {
        Elixir_String["contains?/2"](Type.bitstring("abc"), Type.integer(1));
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "binary",
          function: "match",
          arityOrArgs: Type.list([Type.bitstring("abc"), Type.integer(1)]),
          file: null,
          line: null,
          errorInfo: Type.map([
            [Type.atom("module"), Type.atom("erl_stdlib_errors")],
          ]),
        },
      ]);
    });
  });

  describe("downcase/1", () => {
    const downcase = Elixir_String["downcase/1"];

    it("delegates to downcase/2", () => {
      const result = downcase(Type.bitstring("HoLoGrAm"));
      const expected = Type.bitstring("hologram");

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("downcase/2", () => {
    const downcase = Elixir_String["downcase/2"];

    const string = Type.bitstring("HoLoGrAm");
    const mode = Type.atom("default");

    describe("default mode", () => {
      it("ASCII string", () => {
        const result = downcase(string, mode);
        const expected = Type.bitstring("hologram");

        assert.deepStrictEqual(result, expected);
      });

      it("Unicode string", () => {
        const result = downcase(Type.bitstring("ŹRÓDŁO"), mode);
        const expected = Type.bitstring("źródło");

        assert.deepStrictEqual(result, expected);
      });
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the first arg is not a bitstring", () => {
      const arg1 = Type.atom("abc");

      assertBoxedError(
        () => downcase(arg1, mode),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.downcase/2", [arg1, mode]),
      );
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the first arg is a non-binary bitstring", () => {
      const arg1 = Type.bitstring([1, 0, 1, 0]);

      assertBoxedError(
        () => downcase(arg1, mode),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.downcase/2", [arg1, mode]),
      );
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the second arg is not an atom", () => {
      const arg2 = Type.integer(123);

      assertBoxedError(
        () => downcase(string, arg2),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.downcase/2", [string, arg2]),
      );
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the second arg is an atom, but is not a valid mode", () => {
      const arg2 = Type.atom("abc");

      assertBoxedError(
        () => downcase(string, arg2),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.downcase/2", [string, arg2]),
      );
    });

    // TODO: remove once modes other than :default are implemented
    it("raises HologramInterpreterError if mode is different than :default", () => {
      const arg2 = Type.atom("ascii");

      assert.throw(
        () => downcase(string, arg2),
        HologramInterpreterError,
        "String.downcase/2 modes other than :default are not yet implemented in Hologram",
      );
    });

    it("error frame carries args", () => {
      let caught;

      try {
        Elixir_String["downcase/2"](Type.atom("abc"), Type.atom("default"));
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "String",
          function: "downcase",
          arityOrArgs: Type.list([Type.atom("abc"), Type.atom("default")]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });

  describe("replace/3", () => {
    const replace = Elixir_String["replace/3"];

    const subject = Type.bitstring("abcabc");
    const pattern = Type.bitstring("ab");
    const replacement = Type.bitstring("xy");

    it("ASCII text", () => {
      const result = replace(subject, pattern, replacement);
      const expected = Type.bitstring("xycxyc");

      assert.deepStrictEqual(result, expected);
    });

    it("Unicode text", () => {
      const subject = Type.bitstring("全息图全息图");
      const pattern = Type.bitstring("全息");

      const result = replace(subject, pattern, replacement);
      const expected = Type.bitstring("xy图xy图");

      assert.deepStrictEqual(result, expected);
    });

    it("grapheme 'é' which is made of the characters 'e' and the acute accent (replacing across grapheme boundaries)", () => {
      // String.normalize("é", :nfd)
      const subject = Type.bitstring("é");

      const pattern = Type.bitstring("e");
      const replacement = Type.bitstring("o");

      const result = replace(subject, pattern, replacement);
      const expected = Type.bitstring("ó");

      assert.deepStrictEqual(result, expected);
    });

    it("grapheme 'é' which is represented by the single character 'e with acute' accent (no replacing at all)", () => {
      // String.normalize("é", :nfc)
      const subject = Type.bitstring("é");

      const pattern = Type.bitstring("e");
      const replacement = Type.bitstring("o");

      const result = replace(subject, pattern, replacement);
      const expected = Type.bitstring("é");

      assert.deepStrictEqual(result, expected);
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("non-binary subject arg", () => {
      const subject = Type.atom("abc");

      assertBoxedError(
        () => replace(subject, pattern, replacement),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.replace/4", [
          subject,
          pattern,
          replacement,
          Type.list(),
        ]),
      );
    });

    // TODO: remove when String.replace/3 is fully implemented.
    describe("client-only behaviour", () => {
      it("non-binary pattern arg", () => {
        const pattern = Type.atom("ab");

        assert.throw(
          () => replace(subject, pattern, replacement),
          HologramInterpreterError,
          "using String.replace/3 pattern argument other than non-empty binary is not yet implemented in Hologram",
        );
      });

      it("empty binary pattern arg", () => {
        const pattern = Type.bitstring("");

        assert.throw(
          () => replace(subject, pattern, replacement),
          HologramInterpreterError,
          "using String.replace/3 pattern argument other than non-empty binary is not yet implemented in Hologram",
        );
      });

      it("non-binary replacement arg", () => {
        const replacement = Type.atom("xy");

        assert.throw(
          () => replace(subject, pattern, replacement),
          HologramInterpreterError,
          "using String.replace/3 replacement argument other than binary is not yet implemented in Hologram",
        );
      });
    });

    it("error frame carries args", () => {
      let caught;

      try {
        replace(Type.atom("abc"), Type.bitstring("a"), Type.bitstring("b"));
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "String",
          function: "replace",
          arityOrArgs: Type.list([
            Type.atom("abc"),
            Type.bitstring("a"),
            Type.bitstring("b"),
            Type.list(),
          ]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });

  describe("trim/1", () => {
    const trim = Elixir_String["trim/1"];

    it("handles empty bitstrings", () => {
      const bitstring = Type.bitstring("");
      const result = trim(bitstring);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("trims non-empty bitstrings", () => {
      const bitstring = Type.bitstring("  \n\tabc\t\n  ");
      const result = trim(bitstring);

      assert.deepStrictEqual(result, Type.bitstring("abc"));
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the arg is a non-binary bitstring", () => {
      const bitstring = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]);

      assertBoxedError(
        () => trim(bitstring),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.trim/1", [bitstring]),
      );
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the arg is not a bitstring", () => {
      const atom = Type.atom("abc");

      assertBoxedError(
        () => trim(atom),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.trim/1", [atom]),
      );
    });

    it("error frame carries args", () => {
      let caught;

      try {
        Elixir_String["trim/1"](Type.atom("abc"));
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "String",
          function: "trim",
          arityOrArgs: Type.list([Type.atom("abc")]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });

  describe("upcase/1", () => {
    const upcase = Elixir_String["upcase/1"];

    it("delegates to upcase/2", () => {
      const result = upcase(Type.bitstring("HoLoGrAm"));
      const expected = Type.bitstring("HOLOGRAM");

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("upcase/2", () => {
    const upcase = Elixir_String["upcase/2"];

    const string = Type.bitstring("HoLoGrAm");
    const mode = Type.atom("default");

    describe("default mode", () => {
      it("ASCII string", () => {
        const result = upcase(string, mode);
        const expected = Type.bitstring("HOLOGRAM");

        assert.deepStrictEqual(result, expected);
      });

      it("Unicode string", () => {
        const result = upcase(Type.bitstring("źródło"), mode);
        const expected = Type.bitstring("ŹRÓDŁO");

        assert.deepStrictEqual(result, expected);
      });
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the first arg is not a bitstring", () => {
      const arg1 = Type.atom("abc");

      assertBoxedError(
        () => upcase(arg1, mode),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.upcase/2", [arg1, mode]),
      );
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the first arg is a non-binary bitstring", () => {
      const arg1 = Type.bitstring([1, 0, 1, 0]);

      assertBoxedError(
        () => upcase(arg1, mode),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.upcase/2", [arg1, mode]),
      );
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the second arg is not an atom", () => {
      const arg2 = Type.integer(123);

      assertBoxedError(
        () => upcase(string, arg2),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.upcase/2", [string, arg2]),
      );
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the second arg is an atom, but is not a valid mode", () => {
      const arg2 = Type.atom("abc");

      assertBoxedError(
        () => upcase(string, arg2),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg("String.upcase/2", [string, arg2]),
      );
    });

    // TODO: remove once modes other than :default are implemented
    it("raises HologramInterpreterError if mode is different than :default", () => {
      const arg2 = Type.atom("ascii");

      assert.throw(
        () => upcase(string, arg2),
        HologramInterpreterError,
        "String.upcase/2 modes other than :default are not yet implemented in Hologram",
      );
    });

    it("error frame carries args", () => {
      let caught;

      try {
        Elixir_String["upcase/2"](Type.atom("abc"), Type.atom("default"));
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "String",
          function: "upcase",
          arityOrArgs: Type.list([Type.atom("abc"), Type.atom("default")]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });
});
