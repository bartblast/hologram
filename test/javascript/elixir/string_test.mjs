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

    describe("default mode", () => {
      const string = Type.bitstring("HoLoGrAm");
      const mode = Type.atom("default");

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
        "modes other than :default are not yet implemented in Hologram",
      );
    });
  });
});
