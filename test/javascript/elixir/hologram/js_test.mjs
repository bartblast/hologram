"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Elixir_Hologram_JS, {
  box,
  resolveBinding,
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
    it("bigint -> native", () => {
      assert.deepStrictEqual(box(42n), {type: "native", value: 42n});
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

describe("resolveBinding()", () => {
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

    const result = resolveBinding(
      Type.atom("MyChart"),
      Type.alias("TestModule1"),
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

    const result = resolveBinding(
      Type.atom("__testObj__"),
      Type.alias("TestModule2"),
    );

    assert.strictEqual(result, globalThis.__testObj__);
  });

  it("unwraps native receiver directly", () => {
    const obj = {a: 1};
    const nativeReceiver = {type: "native", value: obj};

    const result = resolveBinding(nativeReceiver, Type.alias("Unused"));

    assert.strictEqual(result, obj);
  });

  it("unboxes other receiver types", () => {
    const result = resolveBinding(Type.integer(42), Type.alias("Unused"));

    assert.strictEqual(result, 42);
  });
});

describe("unbox()", () => {
  const callerModule = Type.alias("UnboxTestModule");

  beforeEach(() => {
    delete globalThis.Elixir_UnboxTestModule;

    Interpreter.defineManuallyPortedFunction(
      "UnboxTestModule",
      "dummy/0",
      "public",
      () => {},
    );
  });

  describe("atom", () => {
    it("atom true -> true", () => {
      assert.strictEqual(unbox(Type.atom("true"), callerModule), true);
    });

    it("atom false -> false", () => {
      assert.strictEqual(unbox(Type.atom("false"), callerModule), false);
    });

    it("atom nil -> null", () => {
      assert.strictEqual(unbox(Type.atom("nil"), callerModule), null);
    });

    it("atom resolves to module binding", () => {
      class Chart {}

      const moduleProxy = Interpreter.moduleProxy(callerModule);
      moduleProxy.__jsBindings__.set("MyChart", Chart);

      assert.strictEqual(unbox(Type.atom("MyChart"), callerModule), Chart);
    });

    it("atom falls back to string when not in bindings", () => {
      assert.strictEqual(
        unbox(Type.atom("nonexistent"), callerModule),
        "nonexistent",
      );
    });
  });

  describe("bitstring", () => {
    it("bitstring -> string", () => {
      assert.strictEqual(unbox(Type.bitstring("hello"), callerModule), "hello");
    });

    it("empty bitstring -> empty string", () => {
      assert.strictEqual(unbox(Type.bitstring(""), callerModule), "");
    });
  });

  describe("float", () => {
    it("float -> number", () => {
      assert.strictEqual(unbox(Type.float(3.14), callerModule), 3.14);
    });

    it("negative float -> negative number", () => {
      assert.strictEqual(unbox(Type.float(-3.14), callerModule), -3.14);
    });
  });

  describe("integer", () => {
    it("safe integer -> number", () => {
      assert.strictEqual(unbox(Type.integer(42), callerModule), 42);
    });

    it("negative safe integer -> number", () => {
      assert.strictEqual(unbox(Type.integer(-42), callerModule), -42);
    });

    it("0 -> number 0", () => {
      assert.strictEqual(unbox(Type.integer(0), callerModule), 0);
    });

    it("MAX_SAFE_INTEGER -> number", () => {
      assert.strictEqual(
        unbox(Type.integer(9_007_199_254_740_991), callerModule),
        9_007_199_254_740_991,
      );
    });

    it("above MAX_SAFE_INTEGER -> bigint", () => {
      assert.strictEqual(
        unbox(Type.integer(9_007_199_254_740_992n), callerModule),
        9_007_199_254_740_992n,
      );
    });

    it("MIN_SAFE_INTEGER -> number", () => {
      assert.strictEqual(
        unbox(Type.integer(-9_007_199_254_740_991), callerModule),
        -9_007_199_254_740_991,
      );
    });

    it("below MIN_SAFE_INTEGER -> bigint", () => {
      assert.strictEqual(
        unbox(Type.integer(-9_007_199_254_740_992n), callerModule),
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

      assert.deepStrictEqual(unbox(term, callerModule), [1, "two", true]);
    });

    it("empty list -> empty array", () => {
      assert.deepStrictEqual(unbox(Type.list(), callerModule), []);
    });

    it("nested lists -> nested arrays", () => {
      const term = Type.list([
        Type.list([Type.integer(1), Type.integer(2)]),
        Type.list([Type.integer(3)]),
      ]);

      assert.deepStrictEqual(unbox(term, callerModule), [[1, 2], [3]]);
    });
  });

  describe("map", () => {
    it("map -> plain object", () => {
      const term = Type.map([
        [Type.bitstring("a"), Type.integer(1)],
        [Type.bitstring("b"), Type.bitstring("hello")],
      ]);

      assert.deepStrictEqual(unbox(term, callerModule), {a: 1, b: "hello"});
    });

    it("empty map -> empty object", () => {
      assert.deepStrictEqual(unbox(Type.map(), callerModule), {});
    });

    it("atom keys -> string keys", () => {
      const term = Type.map([[Type.atom("name"), Type.bitstring("Alice")]]);

      assert.deepStrictEqual(unbox(term, callerModule), {name: "Alice"});
    });

    it("nested maps -> nested objects", () => {
      const term = Type.map([
        [
          Type.bitstring("a"),
          Type.map([[Type.bitstring("b"), Type.integer(1)]]),
        ],
      ]);

      assert.deepStrictEqual(unbox(term, callerModule), {a: {b: 1}});
    });
  });

  describe("native", () => {
    it("native -> unwrapped value", () => {
      const obj = {a: 1};
      const term = {type: "native", value: obj};

      assert.strictEqual(unbox(term, callerModule), obj);
    });
  });

  describe("tuple", () => {
    it("tuple -> array", () => {
      const term = Type.tuple([Type.integer(1), Type.bitstring("two")]);

      assert.deepStrictEqual(unbox(term, callerModule), [1, "two"]);
    });

    it("empty tuple -> empty array", () => {
      assert.deepStrictEqual(unbox(Type.tuple(), callerModule), []);
    });

    it("nested tuples -> nested arrays", () => {
      const term = Type.tuple([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.tuple([Type.integer(3)]),
      ]);

      assert.deepStrictEqual(unbox(term, callerModule), [[1, 2], [3]]);
    });
  });

  describe("default", () => {
    it("unknown type -> pass through", () => {
      const ref = Type.reference("nonode@nohost", 0, [1, 2, 3]);

      assert.deepStrictEqual(unbox(ref, callerModule), ref);
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
        Type.atom("helpers"),
        Type.atom("add"),
        Type.list([Type.integer(2), Type.integer(3)]),
        Type.alias("CallTestModule"),
      );

      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("resolves atom args to bindings", () => {
      const itemRegistry = {
        register: (item) => item.label,
      };

      const myWidget = {label: "my_widget"};

      Interpreter.defineManuallyPortedFunction(
        "CallTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("CallTestModule"));

      moduleProxy.__jsBindings__.set("Registry", itemRegistry);
      moduleProxy.__jsBindings__.set("Widget", myWidget);

      const result = call(
        Type.atom("Registry"),
        Type.atom("register"),
        Type.list([Type.atom("Widget")]),
        Type.alias("CallTestModule"),
      );

      assert.deepStrictEqual(result, Type.bitstring("my_widget"));
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
        Type.atom("AppConfig"),
        Type.atom("version"),
        Type.alias("GetTestModule"),
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
        Type.atom("AppConfig"),
        Type.atom("missing"),
        Type.alias("GetTestModule"),
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
        Type.atom("Calc"),
        Type.list([Type.integer(10)]),
        Type.alias("NewTestModule"),
      );

      assert.strictEqual(result.type, "native");
      assert.isTrue(result.value instanceof Calculator);
      assert.strictEqual(result.value.initial, 10);
    });

    it("resolves atom args to bindings", () => {
      class DefaultOpts {
        constructor() {
          this.enabled = true;
        }
      }

      class Widget {
        constructor(opts) {
          this.opts = opts;
        }
      }

      Interpreter.defineManuallyPortedFunction(
        "NewTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("NewTestModule"));

      moduleProxy.__jsBindings__.set("MyWidget", Widget);
      moduleProxy.__jsBindings__.set("Options", DefaultOpts);

      const result = new3(
        Type.atom("MyWidget"),
        Type.list([Type.atom("Options")]),
        Type.alias("NewTestModule"),
      );

      assert.strictEqual(result.type, "native");
      assert.isTrue(result.value instanceof Widget);
      assert.strictEqual(result.value.opts, DefaultOpts);
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
        Type.atom("AppSettings"),
        Type.atom("theme"),
        Type.bitstring("dark"),
        Type.alias("SetTestModule"),
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
        Type.atom("AppSettings"),
        Type.atom("theme"),
        Type.bitstring("dark"),
        Type.alias("SetTestModule"),
      );

      assert.deepStrictEqual(result, Type.atom("AppSettings"));
    });

    it("resolves atom value to binding", () => {
      class Theme {
        static name = "dark";
      }

      class Config {
        static activeTheme = null;
      }

      Interpreter.defineManuallyPortedFunction(
        "SetTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("SetTestModule"));

      moduleProxy.__jsBindings__.set("AppConfig", Config);
      moduleProxy.__jsBindings__.set("DarkTheme", Theme);

      set(
        Type.atom("AppConfig"),
        Type.atom("activeTheme"),
        Type.atom("DarkTheme"),
        Type.alias("SetTestModule"),
      );

      assert.strictEqual(Config.activeTheme, Theme);
    });
  });

  describe("typeof/2", () => {
    const typeofFn = Elixir_Hologram_JS["typeof/2"];

    beforeEach(() => {
      delete globalThis.Elixir_TypeofTestModule;

      Interpreter.defineManuallyPortedFunction(
        "TypeofTestModule",
        "dummy/0",
        "public",
        () => {},
      );
    });

    it("integer -> number", () => {
      const result = typeofFn(Type.integer(42), Type.alias("TypeofTestModule"));

      assert.deepStrictEqual(result, Type.bitstring("number"));
    });

    it("float -> number", () => {
      const result = typeofFn(Type.float(3.14), Type.alias("TypeofTestModule"));

      assert.deepStrictEqual(result, Type.bitstring("number"));
    });

    it("bitstring -> string", () => {
      const result = typeofFn(
        Type.bitstring("hello"),
        Type.alias("TypeofTestModule"),
      );

      assert.deepStrictEqual(result, Type.bitstring("string"));
    });

    it("boolean true -> boolean", () => {
      const result = typeofFn(
        Type.atom("true"),
        Type.alias("TypeofTestModule"),
      );

      assert.deepStrictEqual(result, Type.bitstring("boolean"));
    });

    it("nil -> object", () => {
      const result = typeofFn(Type.atom("nil"), Type.alias("TypeofTestModule"));

      assert.deepStrictEqual(result, Type.bitstring("object"));
    });

    it("native object -> object", () => {
      class MyClass {}
      const instance = new MyClass();

      const result = typeofFn(
        {type: "native", value: instance},
        Type.alias("TypeofTestModule"),
      );

      assert.deepStrictEqual(result, Type.bitstring("object"));
    });

    it("binding to a class -> function", () => {
      class Calculator {}

      const moduleProxy = Interpreter.moduleProxy(
        Type.alias("TypeofTestModule"),
      );

      moduleProxy.__jsBindings__.set("Calculator", Calculator);

      const result = typeofFn(
        Type.atom("Calculator"),
        Type.alias("TypeofTestModule"),
      );

      assert.deepStrictEqual(result, Type.bitstring("function"));
    });

    it("atom not in bindings -> string", () => {
      const result = typeofFn(
        Type.atom("nonExistentBinding"),
        Type.alias("TypeofTestModule"),
      );

      assert.deepStrictEqual(result, Type.bitstring("string"));
    });
  });
});
