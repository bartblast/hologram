import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_URI from "../../../assets/js/elixir/uri.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/uri_test.exs
// Always update both together.

describe("Elixir_URI", () => {
  describe("encode/2", () => {
    const encode = Elixir_URI["encode/2"];

    describe("with &URI.char_unreserved?/1 predicate", () => {
      let predicate;

      beforeEach(() => {
        predicate = Type.functionCapture(
          "URI",
          "char_unreserved?",
          1,
          [],
          contextFixture(),
        );
      });

      it("encodes empty string", () => {
        const string = Type.bitstring("");
        const result = encode(string, predicate);
        const expected = Type.bitstring("");

        assert.deepStrictEqual(result, expected);
      });

      it("does not encode unreserved ASCII alphanumeric characters", () => {
        const text =
          "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        const string = Type.bitstring(text);

        const result = encode(string, predicate);
        const expected = Type.bitstring(text);

        assert.deepStrictEqual(result, expected);
      });

      it("does not encode unreserved special characters: - . _ ~", () => {
        const text = "-._~";
        const string = Type.bitstring(text);
        const result = encode(string, predicate);
        const expected = Type.bitstring(text);

        assert.deepStrictEqual(result, expected);
      });

      it("encodes reserved URI characters", () => {
        const string = Type.bitstring(":/?#[]@!$&'()*+,;=");
        const result = encode(string, predicate);

        const expected = Type.bitstring(
          "%3A%2F%3F%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D",
        );

        assert.deepStrictEqual(result, expected);
      });

      it("encodes UTF-8 multi-byte characters", () => {
        const string = Type.bitstring("全息图");
        const result = encode(string, predicate);
        const expected = Type.bitstring("%E5%85%A8%E6%81%AF%E5%9B%BE");

        assert.deepStrictEqual(result, expected);
      });

      it("handles already percent-encoded strings (double encodes)", () => {
        const string = Type.bitstring("hello%20world");
        const result = encode(string, predicate);
        const expected = Type.bitstring("hello%2520world");

        assert.deepStrictEqual(result, expected);
      });

      it("encodes control characters", () => {
        const string = Type.bitstring("line1\nline2\ttab");
        const result = encode(string, predicate);
        const expected = Type.bitstring("line1%0Aline2%09tab");

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("with custom predicate", () => {
      it("encodes characters not matching custom predicate", () => {
        // Custom predicate that only allows lowercase letters a-z
        const predicate = Type.anonymousFunction(
          1,
          [
            {
              params: (_context) => [Type.variablePattern("char")],
              guards: [],
              body: (context) => {
                const char = context.vars.char;
                const value = char.value;
                const matches = value >= 97 && value <= 122; // a-z
                return Type.boolean(matches);
              },
            },
          ],
          contextFixture(),
        );

        const string = Type.bitstring("Hello123");
        const result = encode(string, predicate);
        const expected = Type.bitstring("%48ello%31%32%33");

        assert.deepStrictEqual(result, expected);
      });

      it("encodes all characters when predicate always returns false", () => {
        const predicate = Type.anonymousFunction(
          1,
          [
            {
              params: (_context) => [Type.variablePattern("char")],
              guards: [],
              body: (_context) => Type.boolean(false),
            },
          ],
          contextFixture(),
        );

        const string = Type.bitstring("abc");
        const result = encode(string, predicate);
        const expected = Type.bitstring("%61%62%63");

        assert.deepStrictEqual(result, expected);
      });

      it("encodes no characters when predicate always returns true", () => {
        const predicate = Type.anonymousFunction(
          1,
          [
            {
              params: (_context) => [Type.variablePattern("char")],
              guards: [],
              body: (_context) => Type.boolean(true),
            },
          ],
          contextFixture(),
        );

        const string = Type.bitstring("Hello World!");
        const result = encode(string, predicate);

        assertBoxedStrictEqual(result, string);
      });
    });

    describe("error cases", () => {
      it("raises FunctionClauseError when first argument is not a bitstring", () => {
        const string = Type.atom("hello");

        const predicate = Type.functionCapture(
          "URI",
          "char_unreserved?",
          1,
          [],
          contextFixture(),
        );

        assertBoxedError(
          () => encode(string, predicate),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg("URI.encode/2", [
            string,
            predicate,
          ]),
        );
      });

      it("raises FunctionClauseError when first argument is a non-binary bitstring", () => {
        const string = Type.bitstring([1, 0, 1, 0]);

        const predicate = Type.functionCapture(
          "URI",
          "char_unreserved?",
          1,
          [],
          contextFixture(),
        );

        assertBoxedError(
          () => encode(string, predicate),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg("URI.encode/2", [
            string,
            predicate,
          ]),
        );
      });

      it("raises FunctionClauseError when second argument is not a function", () => {
        const string = Type.bitstring("hello");
        const predicate = Type.atom("not_a_function");

        assertBoxedError(
          () => encode(string, predicate),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg("URI.encode/2", [
            string,
            predicate,
          ]),
        );
      });

      it("raises FunctionClauseError when predicate arity is not 1", () => {
        const string = Type.bitstring("hello");

        const predicate = Type.anonymousFunction(
          2,
          [
            {
              params: (_context) => [
                Type.variablePattern("a"),
                Type.variablePattern("b"),
              ],
              guards: [],
              body: (_context) => Type.boolean(true),
            },
          ],
          contextFixture(),
        );

        assertBoxedError(
          () => encode(string, predicate),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg("URI.encode/2", [
            string,
            predicate,
          ]),
        );
      });
    });
  });
});
