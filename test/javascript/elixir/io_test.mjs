import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "../support/helpers.mjs";

import Elixir_IO from "../../../assets/js/elixir/io.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/io_test.exs
// Always update both together.

describe("Elixir_IO", () => {
  let consoleLogStub;

  beforeEach(() => {
    consoleLogStub = sinon.stub(console, "log").callsFake((_msg) => undefined);
  });

  afterEach(() => {
    console.log.restore();
  });

  describe("inspect/1", () => {
    const inspect = Elixir_IO["inspect/1"];

    it("delegates to inspect/2", () => {
      const term = Type.boolean(true);
      const result = inspect(term);

      assert.deepStrictEqual(result, term);

      sinon.assert.calledOnceWithExactly(consoleLogStub, "true\n");
    });
  });

  describe("inspect/2", () => {
    const inspect = Elixir_IO["inspect/2"];

    it("delegates to inspect/3", () => {
      const term = Type.map([
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("a"), Type.integer(1)],
      ]);

      const opts = Type.keywordList([
        [
          Type.atom("custom_options"),
          Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
        ],
      ]);

      const result = inspect(term, opts);

      assert.deepStrictEqual(result, term);

      sinon.assert.calledOnceWithExactly(consoleLogStub, "%{a: 1, b: 2}\n");
    });
  });

  // Also see Interpreter.inspect() consistency tests
  describe("inspect/3", () => {
    const inspect = Elixir_IO["inspect/3"];

    it("uses Interpreter.inspect()", () => {
      const device = Type.atom("stdio");

      const term = Type.map([
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("a"), Type.integer(1)],
      ]);

      const opts = Type.keywordList([
        [
          Type.atom("custom_options"),
          Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
        ],
      ]);

      const result = inspect(device, term, opts);

      assert.deepStrictEqual(result, term);

      sinon.assert.calledOnceWithExactly(consoleLogStub, "%{a: 1, b: 2}\n");
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the first arg is not an atom or a pid", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        "IO.inspect/3",
        [Type.integer(123), Type.atom("abc"), Type.keywordList()],
      );

      assertBoxedError(
        () => inspect(Type.integer(123), Type.atom("abc"), Type.keywordList()),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    describe("client-only behaviour", () => {
      const term = Type.atom("abc");
      const opts = Type.keywordList();

      it("raises HologramInterpreterError if the given device is a PID", () => {
        const device = Type.pid("my_node@my_host", [0, 11, 222], "client");

        assert.throw(
          () => inspect(device, term, opts),
          HologramInterpreterError,
          `device #PID<0.11.222> was attempted to be used on the client side (only :stdio and :stderr devices are available)"`,
        );
      });

      it("raises HologramInterpreterError if the given device is an atom other than :stdio or :stderr", () => {
        const device = Type.atom("std123");

        assert.throw(
          () => inspect(device, term, opts),
          HologramInterpreterError,
          `device :std123 was attempted to be used on the client side (only :stdio and :stderr devices are available)"`,
        );
      });
    });
  });
});
