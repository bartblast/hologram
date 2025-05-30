import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_String from "../../../assets/js/elixir/string.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/string_test.exs
// Always update both together.

describe("Elixir_String", () => {
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

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the first arg is not a bitstring", () => {
      const arg1 = Type.atom("abc");

      assertBoxedError(
        () => downcase(arg1, mode),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.downcase/2", [
          arg1,
          mode,
        ]),
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the first arg is a non-binary bitstring", () => {
      const arg1 = Type.bitstring([1, 0, 1, 0]);

      assertBoxedError(
        () => downcase(arg1, mode),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.downcase/2", [
          arg1,
          mode,
        ]),
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the second arg is not an atom", () => {
      const arg2 = Type.integer(123);

      assertBoxedError(
        () => downcase(string, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.downcase/2", [
          string,
          arg2,
        ]),
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the second arg is an atom, but is not a valid mode", () => {
      const arg2 = Type.atom("abc");

      assertBoxedError(
        () => downcase(string, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.downcase/2", [
          string,
          arg2,
        ]),
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

    // TODO: client error message for this case is inconsistent with server error message
    it("non-binary subject arg", () => {
      const subject = Type.atom("abc");

      assertBoxedError(
        () => replace(subject, pattern, replacement),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.replace/4", [
          subject,
          pattern,
          replacement,
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

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the first arg is not a bitstring", () => {
      const arg1 = Type.atom("abc");

      assertBoxedError(
        () => upcase(arg1, mode),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.upcase/2", [
          arg1,
          mode,
        ]),
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the first arg is a non-binary bitstring", () => {
      const arg1 = Type.bitstring([1, 0, 1, 0]);

      assertBoxedError(
        () => upcase(arg1, mode),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.upcase/2", [
          arg1,
          mode,
        ]),
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the second arg is not an atom", () => {
      const arg2 = Type.integer(123);

      assertBoxedError(
        () => upcase(string, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.upcase/2", [
          string,
          arg2,
        ]),
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the second arg is an atom, but is not a valid mode", () => {
      const arg2 = Type.atom("abc");

      assertBoxedError(
        () => upcase(string, arg2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("String.upcase/2", [
          string,
          arg2,
        ]),
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
  });
});
