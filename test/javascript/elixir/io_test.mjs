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

  describe("warn/1", () => {
    let consoleWarnStub;

    beforeEach(() => {
      consoleWarnStub = sinon
        .stub(console, "warn")
        .callsFake((_msg) => undefined);
    });

    afterEach(() => {
      console.warn.restore();
    });

    const warn = Elixir_IO["warn/1"];

    it("delegates to warn/2", () => {
      const result = warn(Type.bitstring("my warning"));

      assert.deepStrictEqual(result, Type.atom("ok"));
      sinon.assert.calledOnceWithExactly(consoleWarnStub, "my warning");
    });
  });

  describe("warn/2", () => {
    let consoleWarnStub;

    beforeEach(() => {
      consoleWarnStub = sinon
        .stub(console, "warn")
        .callsFake((_msg) => undefined);
    });

    afterEach(() => {
      console.warn.restore();
    });

    const warn = Elixir_IO["warn/2"];

    it("handles string message", () => {
      const result = warn(Type.bitstring("my warning"), Type.list());

      assert.deepStrictEqual(result, Type.atom("ok"));
      sinon.assert.calledOnceWithExactly(consoleWarnStub, "my warning");
    });

    it("handles iodata message", () => {
      const message = Type.list([
        Type.bitstring("hello"),
        Type.bitstring(" "),
        Type.bitstring("world"),
      ]);

      const result = warn(message, Type.list());

      assert.deepStrictEqual(result, Type.atom("ok"));
      sinon.assert.calledOnceWithExactly(consoleWarnStub, "hello world");
    });
  });

  describe("warn_once/3", () => {
    let consoleWarnStub;

    beforeEach(() => {
      consoleWarnStub = sinon
        .stub(console, "warn")
        .callsFake((_msg) => undefined);
    });

    afterEach(() => {
      console.warn.restore();
    });

    const warn_once = Elixir_IO["warn_once/3"];

    it("evaluates message function and warns", () => {
      const messageFun = Type.anonymousFunction(
        0,
        [
          {
            params: () => [],
            guards: [],
            body: () => Type.bitstring("my warning"),
          },
        ],
        {},
      );

      const result = warn_once(
        Type.atom("my_key"),
        messageFun,
        Type.integer(0),
      );

      assert.deepStrictEqual(result, Type.atom("ok"));
      sinon.assert.calledOnceWithExactly(consoleWarnStub, "my warning");
    });
  });
});
