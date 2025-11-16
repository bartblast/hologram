import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_Bitwise from "../../../assets/js/elixir/bitwise.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Elixir_Bitwise", () => {
  describe("band/2 and &&&/2", () => {
    const band = Elixir_Bitwise["band/2"];
    const operator = Elixir_Bitwise["&&&/2"];

    it("calculates bitwise AND", () => {
      const result = band(Type.integer(9), Type.integer(3));
      const expected = Type.integer(1);

      assert.deepStrictEqual(result, expected);
    });

    it("handles negative operands", () => {
      const result = operator(Type.integer(-5), Type.integer(12));
      const expected = Type.integer(8n & -5n);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArithmeticError when an operand is not an integer", () => {
      const left = Type.atom("foo");
      const right = Type.integer(1);

      assertBoxedError(
        () => band(left, right),
        "ArithmeticError",
        "bad argument in arithmetic expression: Bitwise.band(:foo, 1)",
      );
    });
  });

  describe("bor/2 and |||/2", () => {
    const bor = Elixir_Bitwise["bor/2"];
    const operator = Elixir_Bitwise["|||/2"];

    it("calculates bitwise OR", () => {
      const result = bor(Type.integer(9), Type.integer(3));
      const expected = Type.integer(11);

      assert.deepStrictEqual(result, expected);
    });

    it("supports operator form", () => {
      const result = operator(Type.integer(-5), Type.integer(12));
      const expected = Type.integer(-5n | 12n);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("bxor/2 and ^^^/2", () => {
    const bxor = Elixir_Bitwise["bxor/2"];
    const operator = Elixir_Bitwise["^^^/2"];

    it("calculates bitwise XOR", () => {
      const result = bxor(Type.integer(9), Type.integer(3));
      const expected = Type.integer(10);

      assert.deepStrictEqual(result, expected);
    });

    it("supports operator form", () => {
      const result = operator(Type.integer(-5), Type.integer(12));
      const expected = Type.integer(-5n ^ 12n);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("bnot/1 and ~~~/1", () => {
    const bnot = Elixir_Bitwise["bnot/1"];
    const operator = Elixir_Bitwise["~~~/1"];

    it("calculates bitwise NOT", () => {
      const result = bnot(Type.integer(2));
      const expected = Type.integer(-3);

      assert.deepStrictEqual(result, expected);
    });

    it("supports operator form", () => {
      const result = operator(Type.integer(-1));
      const expected = Type.integer(~-1n);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("bsl/2 and <<</2", () => {
    const bsl = Elixir_Bitwise["bsl/2"];
    const operator = Elixir_Bitwise["<<</2"];

    it("shifts left for positive shift counts", () => {
      const result = bsl(Type.integer(1), Type.integer(3));
      const expected = Type.integer(8);

      assert.deepStrictEqual(result, expected);
    });

    it("converts negative shift counts to right shifts", () => {
      const result = bsl(Type.integer(1), Type.integer(-2));
      const expected = Type.integer(0);

      assert.deepStrictEqual(result, expected);
    });

    it("supports operator form", () => {
      const result = operator(Type.integer(-1), Type.integer(2));
      const expected = Type.integer(-1n << 2n);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("bsr/2 and >>>/2", () => {
    const bsr = Elixir_Bitwise["bsr/2"];
    const operator = Elixir_Bitwise[">>>/2"];

    it("shifts right for positive shift counts", () => {
      const result = bsr(Type.integer(9), Type.integer(2));
      const expected = Type.integer(2);

      assert.deepStrictEqual(result, expected);
    });

    it("converts negative shift counts to left shifts", () => {
      const result = bsr(Type.integer(1), Type.integer(-2));
      const expected = Type.integer(4);

      assert.deepStrictEqual(result, expected);
    });

    it("supports operator form", () => {
      const result = operator(Type.integer(-8), Type.integer(2));
      const expected = Type.integer(-8n >> 2n);

      assert.deepStrictEqual(result, expected);
    });
  });
});
