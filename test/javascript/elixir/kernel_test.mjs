import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Elixir_Kernel from "../../../assets/js/elixir/kernel.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/kernel_test.exs
// Always update both together.

describe("inspect/1", () => {
  it("delegates to inspect/2", () => {
    const result = Elixir_Kernel["inspect/1"](Type.boolean(true));
    assert.deepStrictEqual(result, Type.bitstring("true"));
  });
});

describe("inspect/2", () => {
  const opts = Type.list([]);

  describe("atom", () => {
    it("true", () => {
      const result = Elixir_Kernel["inspect/2"](Type.boolean(true), opts);
      assert.deepStrictEqual(result, Type.bitstring("true"));
    });

    it("false", () => {
      const result = Elixir_Kernel["inspect/2"](Type.boolean(false), opts);
      assert.deepStrictEqual(result, Type.bitstring("false"));
    });

    it("nil", () => {
      const result = Elixir_Kernel["inspect/2"](Type.nil(), opts);
      assert.deepStrictEqual(result, Type.bitstring("nil"));
    });

    it("non-boolean and non-nil", () => {
      const result = Elixir_Kernel["inspect/2"](Type.atom("abc"), opts);
      assert.deepStrictEqual(result, Type.bitstring(":abc"));
    });

    describe("float", () => {
      it("integer-representable", () => {
        const result = Elixir_Kernel["inspect/2"](Type.float(123.0), opts);
        assert.deepStrictEqual(result, Type.bitstring("123.0"));
      });

      it("not integer-representable", () => {
        const result = Elixir_Kernel["inspect/2"](Type.float(123.45), opts);
        assert.deepStrictEqual(result, Type.bitstring("123.45"));
      });
    });

    it("integer", () => {
      const result = Elixir_Kernel["inspect/2"](Type.integer(123), opts);
      assert.deepStrictEqual(result, Type.bitstring("123"));
    });
  });

  // TODO: remove when all types are supported
  it("default", () => {
    const result = Elixir_Kernel["inspect/2"]({type: "x"}, Type.list([]));
    assert.deepStrictEqual(result, Type.bitstring('{"type":"x"}'));
  });
});
