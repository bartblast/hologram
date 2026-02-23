"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Elixir_Hologram_JS, {
  box,
  resolveReceiver,
  unbox,
} from "../../../../assets/js/elixir/hologram/js.mjs";

import Interpreter from "../../../../assets/js/interpreter.mjs";
import Type from "../../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("box()", () => {
  describe("nullish", () => {
    it("null -> atom nil", () => {
      assert.deepStrictEqual(box(null), Type.atom("nil"));
    });

    it("undefined -> atom nil", () => {
      assert.deepStrictEqual(box(undefined), Type.atom("nil"));
    });
  });

  describe("boolean", () => {
    it("true -> atom true", () => {
      assert.deepStrictEqual(box(true), Type.atom("true"));
    });

    it("false -> atom false", () => {
      assert.deepStrictEqual(box(false), Type.atom("false"));
    });
  });

  describe("number", () => {
    it("bigint -> integer", () => {
      // Number.MAX_SAFE_INTEGER = 9_007_199_254_740_991
      assert.deepStrictEqual(
        box(9_007_199_254_740_992n),
        Type.integer(9_007_199_254_740_992n),
      );
    });

    it("negative bigint -> integer", () => {
      // Number.MIN_SAFE_INTEGER = -9_007_199_254_740_991
      assert.deepStrictEqual(
        box(-9_007_199_254_740_991n),
        Type.integer(-9_007_199_254_740_991n),
      );
    });

    it("integer number -> integer", () => {
      assert.deepStrictEqual(box(42), Type.integer(42));
    });

    it("negative integer number -> integer", () => {
      assert.deepStrictEqual(box(-42), Type.integer(-42));
    });

    it("float number -> float", () => {
      assert.deepStrictEqual(box(3.14), Type.float(3.14));
    });

    it("negative float number -> float", () => {
      assert.deepStrictEqual(box(-3.14), Type.float(-3.14));
    });

    it("0 -> integer", () => {
      assert.deepStrictEqual(box(0), Type.integer(0));
    });

    it("0.0 -> integer", () => {
      assert.deepStrictEqual(box(0.0), Type.integer(0));
    });

    it("+0.0 -> integer", () => {
      assert.deepStrictEqual(box(+0.0), Type.integer(0));
    });

    it("-0.0 -> integer", () => {
      assert.deepStrictEqual(box(-0.0), Type.integer(0));
    });
  });

  describe("string", () => {
    it("string -> bitstring", () => {
      assert.deepStrictEqual(box("hello"), Type.bitstring("hello"));
    });

    it("empty string -> bitstring", () => {
      assert.deepStrictEqual(box(""), Type.bitstring(""));
    });
  });

  describe("array", () => {
    it("array -> list", () => {
      const result = box([1, "two", true]);

      const expected = Type.list([
        Type.integer(1),
        Type.bitstring("two"),
        Type.boolean(true),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("empty array -> empty list", () => {
      assert.deepStrictEqual(box([]), Type.list());
    });

    it("nested arrays -> nested lists", () => {
      const result = box([[1, 2], [3]]);

      const expected = Type.list([
        Type.list([Type.integer(1), Type.integer(2)]),
        Type.list([Type.integer(3)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("plain object", () => {
    it("plain object -> map", () => {
      const result = box({a: 1, b: "hello"});

      const expected = Type.map([
        [Type.bitstring("a"), Type.integer(1)],
        [Type.bitstring("b"), Type.bitstring("hello")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("empty object -> empty map", () => {
      assert.deepStrictEqual(box({}), Type.map());
    });

    it("nested plain objects -> nested maps", () => {
      const result = box({a: {b: 1}});

      const expected = Type.map([
        [
          Type.bitstring("a"),
          Type.map([[Type.bitstring("b"), Type.integer(1)]]),
        ],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("null prototype object -> map", () => {
      const obj = Object.create(null);
      obj.a = 1;

      const result = box(obj);

      const expected = Type.map([[Type.bitstring("a"), Type.integer(1)]]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("native", () => {
    it("function -> native", () => {
      const fn = () => 42;
      const result = box(fn);

      assert.deepStrictEqual(result, {type: "native", value: fn});
    });

    it("class instance -> native", () => {
      class MyClass {}
      const instance = new MyClass();
      const result = box(instance);

      assert.deepStrictEqual(result, {type: "native", value: instance});
    });
  });
});

describe("resolveReceiver()", () => {
  beforeEach(() => {
    delete globalThis.Elixir_TestModule1;
    delete globalThis.Elixir_TestModule2;
    delete globalThis.__testObj__;
  });

  it("resolves from module's JS bindings when receiver is an atom", () => {
    class Chart {
      render() {}
    }

    Interpreter.defineManuallyPortedFunction(
      "TestModule1",
      "dummy/0",
      "public",
      () => {},
    );

    const moduleProxy = Interpreter.moduleProxy(Type.alias("TestModule1"));
    moduleProxy.__jsBindings__.set("MyChart", Chart);

    const result = resolveReceiver(
      Type.alias("TestModule1"),
      Type.atom("MyChart"),
    );

    assert.strictEqual(result, Chart);
  });

  it("falls back to globalThis when not in bindings", () => {
    globalThis.__testObj__ = {x: 42};

    Interpreter.defineManuallyPortedFunction(
      "TestModule2",
      "dummy/0",
      "public",
      () => {},
    );

    const result = resolveReceiver(
      Type.alias("TestModule2"),
      Type.atom("__testObj__"),
    );

    assert.strictEqual(result, globalThis.__testObj__);
  });

  it("unwraps native receiver directly", () => {
    const obj = {a: 1};
    const nativeReceiver = {type: "native", value: obj};

    const result = resolveReceiver(Type.alias("Unused"), nativeReceiver);

    assert.strictEqual(result, obj);
  });

  it("unboxes other receiver types", () => {
    const result = resolveReceiver(Type.alias("Unused"), Type.integer(42));

    assert.strictEqual(result, 42);
  });
});

describe("unbox()", () => {
  describe("atom", () => {
    it("atom true -> true", () => {
      assert.strictEqual(unbox(Type.atom("true")), true);
    });

    it("atom false -> false", () => {
      assert.strictEqual(unbox(Type.atom("false")), false);
    });

    it("atom nil -> null", () => {
      assert.strictEqual(unbox(Type.atom("nil")), null);
    });

    it("other atom -> string", () => {
      assert.strictEqual(unbox(Type.atom("hello")), "hello");
    });
  });

  describe("bitstring", () => {
    it("bitstring -> string", () => {
      assert.strictEqual(unbox(Type.bitstring("hello")), "hello");
    });

    it("empty bitstring -> empty string", () => {
      assert.strictEqual(unbox(Type.bitstring("")), "");
    });
  });

  describe("float", () => {
    it("float -> number", () => {
      assert.strictEqual(unbox(Type.float(3.14)), 3.14);
    });

    it("negative float -> negative number", () => {
      assert.strictEqual(unbox(Type.float(-3.14)), -3.14);
    });
  });

  describe("integer", () => {
    it("safe integer -> number", () => {
      assert.strictEqual(unbox(Type.integer(42)), 42);
    });

    it("negative safe integer -> number", () => {
      assert.strictEqual(unbox(Type.integer(-42)), -42);
    });

    it("0 -> number 0", () => {
      assert.strictEqual(unbox(Type.integer(0)), 0);
    });

    it("MAX_SAFE_INTEGER -> number", () => {
      assert.strictEqual(
        unbox(Type.integer(9_007_199_254_740_991)),
        9_007_199_254_740_991,
      );
    });

    it("above MAX_SAFE_INTEGER -> bigint", () => {
      assert.strictEqual(
        unbox(Type.integer(9_007_199_254_740_992n)),
        9_007_199_254_740_992n,
      );
    });

    it("MIN_SAFE_INTEGER -> number", () => {
      assert.strictEqual(
        unbox(Type.integer(-9_007_199_254_740_991)),
        -9_007_199_254_740_991,
      );
    });

    it("below MIN_SAFE_INTEGER -> bigint", () => {
      assert.strictEqual(
        unbox(Type.integer(-9_007_199_254_740_992n)),
        -9_007_199_254_740_992n,
      );
    });
  });

  describe("list", () => {
    it("list -> array", () => {
      const term = Type.list([
        Type.integer(1),
        Type.bitstring("two"),
        Type.atom("true"),
      ]);

      assert.deepStrictEqual(unbox(term), [1, "two", true]);
    });

    it("empty list -> empty array", () => {
      assert.deepStrictEqual(unbox(Type.list()), []);
    });

    it("nested lists -> nested arrays", () => {
      const term = Type.list([
        Type.list([Type.integer(1), Type.integer(2)]),
        Type.list([Type.integer(3)]),
      ]);

      assert.deepStrictEqual(unbox(term), [[1, 2], [3]]);
    });
  });

  describe("map", () => {
    it("map -> plain object", () => {
      const term = Type.map([
        [Type.bitstring("a"), Type.integer(1)],
        [Type.bitstring("b"), Type.bitstring("hello")],
      ]);

      assert.deepStrictEqual(unbox(term), {a: 1, b: "hello"});
    });

    it("empty map -> empty object", () => {
      assert.deepStrictEqual(unbox(Type.map()), {});
    });

    it("atom keys -> string keys", () => {
      const term = Type.map([[Type.atom("name"), Type.bitstring("Alice")]]);

      assert.deepStrictEqual(unbox(term), {name: "Alice"});
    });

    it("nested maps -> nested objects", () => {
      const term = Type.map([
        [
          Type.bitstring("a"),
          Type.map([[Type.bitstring("b"), Type.integer(1)]]),
        ],
      ]);

      assert.deepStrictEqual(unbox(term), {a: {b: 1}});
    });
  });

  describe("native", () => {
    it("native -> unwrapped value", () => {
      const obj = {a: 1};
      const term = {type: "native", value: obj};

      assert.strictEqual(unbox(term), obj);
    });
  });

  describe("tuple", () => {
    it("tuple -> array", () => {
      const term = Type.tuple([Type.integer(1), Type.bitstring("two")]);

      assert.deepStrictEqual(unbox(term), [1, "two"]);
    });

    it("empty tuple -> empty array", () => {
      assert.deepStrictEqual(unbox(Type.tuple()), []);
    });

    it("nested tuples -> nested arrays", () => {
      const term = Type.tuple([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.tuple([Type.integer(3)]),
      ]);

      assert.deepStrictEqual(unbox(term), [[1, 2], [3]]);
    });
  });

  describe("default", () => {
    it("unknown type -> pass through", () => {
      const ref = Type.reference("nonode@nohost", 0, [1, 2, 3]);

      assert.deepStrictEqual(unbox(ref), ref);
    });
  });
});

describe("Elixir_Hologram_JS", () => {
  describe("call/4", () => {
    const call = Elixir_Hologram_JS["call/4"];

    beforeEach(() => {
      delete globalThis.Elixir_CallTestModule;
    });

    it("calls method on receiver with unboxed args and boxes result", () => {
      const mathHelpers = {add: (a, b) => a + b};

      Interpreter.defineManuallyPortedFunction(
        "CallTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("CallTestModule"));

      moduleProxy.__jsBindings__.set("helpers", mathHelpers);

      const result = call(
        Type.alias("CallTestModule"),
        Type.atom("helpers"),
        Type.bitstring("add"),
        Type.list([Type.integer(2), Type.integer(3)]),
      );

      assert.deepStrictEqual(result, Type.integer(5));
    });
  });

  describe("exec/1", () => {
    const exec = Elixir_Hologram_JS["exec/1"];

    it("delegates to Interpreter.evaluateJavaScriptCode()", () => {
      const code = Type.bitstring("return 1 + 2");
      assert.equal(exec(code), 3);
    });
  });

  describe("get/3", () => {
    const get = Elixir_Hologram_JS["get/3"];

    beforeEach(() => {
      delete globalThis.Elixir_GetTestModule;
    });

    it("gets property from receiver and boxes result", () => {
      class Config {
        static version = 3;
      }

      Interpreter.defineManuallyPortedFunction(
        "GetTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("GetTestModule"));

      moduleProxy.__jsBindings__.set("AppConfig", Config);

      const result = get(
        Type.alias("GetTestModule"),
        Type.atom("AppConfig"),
        Type.atom("version"),
      );

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("returns nil for undefined properties", () => {
      class Config {}

      Interpreter.defineManuallyPortedFunction(
        "GetTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("GetTestModule"));

      moduleProxy.__jsBindings__.set("AppConfig", Config);

      const result = get(
        Type.alias("GetTestModule"),
        Type.atom("AppConfig"),
        Type.atom("missing"),
      );

      assert.deepStrictEqual(result, Type.atom("nil"));
    });
  });

  describe("new/3", () => {
    const new3 = Elixir_Hologram_JS["new/3"];

    beforeEach(() => {
      delete globalThis.Elixir_NewTestModule;
    });

    it("instantiates class with unboxed args and boxes result", () => {
      class Calculator {
        constructor(value) {
          this.initial = value;
        }
      }

      Interpreter.defineManuallyPortedFunction(
        "NewTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("NewTestModule"));

      moduleProxy.__jsBindings__.set("Calc", Calculator);

      const result = new3(
        Type.alias("NewTestModule"),
        Type.atom("Calc"),
        Type.list([Type.integer(10)]),
      );

      assert.strictEqual(result.type, "native");
      assert.isTrue(result.value instanceof Calculator);
      assert.strictEqual(result.value.initial, 10);
    });
  });

  describe("set/4", () => {
    const set = Elixir_Hologram_JS["set/4"];

    beforeEach(() => {
      delete globalThis.Elixir_SetTestModule;
    });

    it("sets property on receiver with unboxed value", () => {
      class Settings {
        static theme = "light";
      }

      Interpreter.defineManuallyPortedFunction(
        "SetTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("SetTestModule"));
      moduleProxy.__jsBindings__.set("AppSettings", Settings);

      set(
        Type.alias("SetTestModule"),
        Type.atom("AppSettings"),
        Type.atom("theme"),
        Type.bitstring("dark"),
      );

      assert.strictEqual(Settings.theme, "dark");
    });

    it("returns the receiver", () => {
      class Settings {
        static theme = "light";
      }

      Interpreter.defineManuallyPortedFunction(
        "SetTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("SetTestModule"));
      moduleProxy.__jsBindings__.set("AppSettings", Settings);

      const result = set(
        Type.alias("SetTestModule"),
        Type.atom("AppSettings"),
        Type.atom("theme"),
        Type.bitstring("dark"),
      );

      assert.deepStrictEqual(result, Type.atom("AppSettings"));
    });
  });
});
