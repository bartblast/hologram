import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_Function from "../../../assets/js/elixir/function.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const capture = Elixir_Function["capture/3"];
const info1 = Elixir_Function["info/1"];
const info2 = Elixir_Function["info/2"];
const identity = Elixir_Function["identity/1"];

function defineSampleModule() {
  Interpreter.defineManuallyPortedFunction(
    "Sample",
    "double/1",
    "public",
    (value) => {
      if (!Type.isInteger(value)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg("Sample.double/1", [value]),
        );
      }

      return Type.integer(value.value * 2n);
    },
  );
}

describe("Elixir_Function", () => {
  before(() => {
    defineSampleModule();
  });

  describe("capture/3", () => {
    it("returns a function capture", () => {
      const module = Type.alias("Sample");
      const functionName = Type.atom("double");
      const arity = Type.integer(1);

      const fun = capture(module, functionName, arity);

      const result = Interpreter.callAnonymousFunction(fun, [Type.integer(4)]);
      const expectedResult = Type.integer(8);

      assert.deepStrictEqual(result, expectedResult);
      assert.deepStrictEqual(fun.capturedModule, "Sample");
      assert.equal(fun.capturedFunction, "double");
      assert.equal(fun.arity, 1);
    });

    it("raises ArgumentError when module is not an atom", () => {
      const module = Type.bitstring("Sample");
      const functionName = Type.atom("double");
      const arity = Type.integer(1);

      assertBoxedError(
        () => capture(module, functionName, arity),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    });

    it("raises ArgumentError when function name is not an atom", () => {
      const module = Type.alias("Sample");
      const functionName = Type.bitstring("double");
      const arity = Type.integer(1);

      assertBoxedError(
        () => capture(module, functionName, arity),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    });

    it("raises ArgumentError when arity is not an integer", () => {
      const module = Type.alias("Sample");
      const functionName = Type.atom("double");
      const arity = Type.float(1.0);

      assertBoxedError(
        () => capture(module, functionName, arity),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    });

    it("raises ArgumentError when arity is negative", () => {
      const module = Type.alias("Sample");
      const functionName = Type.atom("double");
      const arity = Type.integer(-1);

      assertBoxedError(
        () => capture(module, functionName, arity),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "out of range"),
      );
    });

    it("raises ArgumentError when arity is too large", () => {
      const module = Type.alias("Sample");
      const functionName = Type.atom("double");
      const arity = Type.integer(256);

      assertBoxedError(
        () => capture(module, functionName, arity),
        "ArgumentError",
        "argument error",
      );
    });
  });

  describe("info/1", () => {
    it("returns a keyword list of function info", () => {
      const module = Type.alias("Sample");
      const functionName = Type.atom("double");
      const arity = Type.integer(1);

      const fun = capture(module, functionName, arity);
      const result = info1(fun);

      const expected = Type.list([
        Type.tuple([Type.atom("module"), module]),
        Type.tuple([Type.atom("name"), functionName]),
        Type.tuple([Type.atom("arity"), Type.integer(1)]),
        Type.tuple([Type.atom("env"), Type.list()]),
        Type.tuple([Type.atom("type"), Type.atom("external")]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError when the first argument is not a function", () => {
      const notFun = Type.integer(1);

      assertBoxedError(
        () => info1(notFun),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a fun"),
      );
    });
  });

  describe("info/2", () => {
    it("returns tuple with requested info item", () => {
      const module = Type.alias("Sample");
      const functionName = Type.atom("double");
      const arity = Type.integer(1);
      const fun = capture(module, functionName, arity);

      const item = Type.atom("arity");
      const result = info2(fun, item);
      const expected = Type.tuple([item, Type.integer(1)]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError when item is invalid", () => {
      const module = Type.alias("Sample");
      const functionName = Type.atom("double");
      const arity = Type.integer(1);
      const fun = capture(module, functionName, arity);

      const invalidItem = Type.atom("invalid");

      assertBoxedError(
        () => info2(fun, invalidItem),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid item"),
      );
    });
  });

  describe("identity/1", () => {
    it("returns the input value", () => {
      const term = Type.bitstring("hologram");

      assert.deepStrictEqual(identity(term), term);
    });
  });
});
