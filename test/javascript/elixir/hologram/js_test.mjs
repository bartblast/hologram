"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  registerWebApis,
} from "../../support/helpers.mjs";

import Elixir_Hologram_JS, {
  resolveBinding,
  unbox,
} from "../../../../assets/js/elixir/hologram/js.mjs";

import {box} from "../../../../assets/js/js_interop.mjs";

import ERTS from "../../../../assets/js/erts.mjs";
import Interpreter from "../../../../assets/js/interpreter.mjs";
import Type from "../../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();
registerWebApis();

describe("box()", () => {
  describe("nullish", () => {
    it("null -> atom nil", () => {
      assert.deepStrictEqual(box(null), Type.atom("nil"));
    });

    it("undefined -> Hologram.JS.NativeValue struct with nil value", () => {
      const result = box(undefined);
      const expected = Type.nativeValueStruct("undefined", Type.nil());

      assert.deepStrictEqual(result, expected);
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
    it("bigint -> Hologram.JS.NativeValue struct with integer value", () => {
      const result = box(42n);
      const expected = Type.nativeValueStruct("bigint", Type.integer(42));

      assert.deepStrictEqual(result, expected);
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

  describe("promise", () => {
    it("promise -> Task struct via ERTS.registerPromise", () => {
      const promise = new Promise((resolve) => resolve(42));
      const result = box(promise);

      assert.isTrue(Type.isStruct(result, "Task"));
    });
  });

  describe("native object", () => {
    it("function -> Hologram.JS.NativeValue struct", () => {
      const fn = () => 42;
      const result = box(fn);

      const valueKey = Type.encodeMapKey(Type.atom("value"));
      const ref = result.data[valueKey][1];

      assert.isTrue(Type.isReference(ref));
      assert.strictEqual(ERTS.nativeObjectRegistry.get(ref), fn);

      const expected = Type.nativeValueStruct("function", ref);

      assert.deepStrictEqual(result, expected);
    });

    it("class instance -> Hologram.JS.NativeValue struct", () => {
      class MyClass {}
      const instance = new MyClass();
      const result = box(instance);

      const valueKey = Type.encodeMapKey(Type.atom("value"));
      const ref = result.data[valueKey][1];

      assert.isTrue(Type.isReference(ref));
      assert.strictEqual(ERTS.nativeObjectRegistry.get(ref), instance);

      const expected = Type.nativeValueStruct("object", ref);

      assert.deepStrictEqual(result, expected);
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

  it("preserves binding whose value is undefined", () => {
    Interpreter.defineManuallyPortedFunction(
      "TestModule1",
      "dummy/0",
      "public",
      () => {},
    );

    const moduleProxy = Interpreter.moduleProxy(Type.alias("TestModule1"));
    moduleProxy.__jsBindings__.set("Foo", undefined);

    globalThis.Foo = {shouldNotReach: true};

    const result = resolveBinding(Type.atom("Foo"), Type.alias("TestModule1"));

    assert.strictEqual(result, undefined);

    delete globalThis.Foo;
  });

  it("preserves binding whose value is null", () => {
    Interpreter.defineManuallyPortedFunction(
      "TestModule1",
      "dummy/0",
      "public",
      () => {},
    );

    const moduleProxy = Interpreter.moduleProxy(Type.alias("TestModule1"));
    moduleProxy.__jsBindings__.set("Bar", null);

    globalThis.Bar = {shouldNotReach: true};

    const result = resolveBinding(Type.atom("Bar"), Type.alias("TestModule1"));

    assert.strictEqual(result, null);

    delete globalThis.Bar;
  });

  it("unboxes Hologram.JS.NativeValue struct from registry", () => {
    class MyClass {}
    const instance = new MyClass();
    const boxedValue = box(instance);

    const result = resolveBinding(boxedValue, Type.alias("Unused"));

    assert.strictEqual(result, instance);
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

  describe("anonymous_function", () => {
    it("wraps anonymous function into a callable JS function", () => {
      const context = Interpreter.buildContext({module: "UnboxTestModule"});

      // fn x -> x end (identity function)
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("x")],
            guards: [],
            body: (context) => {
              return context.vars.x;
            },
          },
        ],
        context,
      );

      const jsFunc = unbox(fun, callerModule);

      assert.isFunction(jsFunc);
      assert.strictEqual(jsFunc(42), 42);
    });

    it("handles multi-arity functions", () => {
      const context = Interpreter.buildContext({module: "UnboxTestModule"});

      // fn a, b -> {a, b} end
      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("a"),
              Type.variablePattern("b"),
            ],
            guards: [],
            body: (context) => {
              return Type.tuple([context.vars.a, context.vars.b]);
            },
          },
        ],
        context,
      );

      const jsFunc = unbox(fun, callerModule);

      assert.deepStrictEqual(jsFunc(3, 4), [3, 4]);
    });

    it("ignores extra JS arguments beyond the function arity", () => {
      const context = Interpreter.buildContext({module: "UnboxTestModule"});

      // fn x -> x end (arity 1, like a callback passed to Array.map)
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("x")],
            guards: [],
            body: (context) => {
              return context.vars.x;
            },
          },
        ],
        context,
      );

      const jsFunc = unbox(fun, callerModule);

      // Array.map passes (element, index, array) — extra args should be ignored
      assert.strictEqual(jsFunc(5, 0, [5, 10, 15]), 5);
    });
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

    it("atom resolves to globalThis property when not in bindings", () => {
      const result = unbox(Type.atom("Math"), callerModule);

      assert.strictEqual(result, Math);
    });

    it("atom falls back to string when not in bindings or globalThis", () => {
      const result = unbox(Type.atom("nonexistent"), callerModule);

      assert.strictEqual(result, "nonexistent");
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

  describe("Hologram.JS.NativeValue struct", () => {
    it("bigint -> bigint", () => {
      const nativeBigInt = 42n;
      const boxedValue = box(nativeBigInt);
      const result = unbox(boxedValue, callerModule);

      assert.strictEqual(result, nativeBigInt);
    });

    it("function -> function", () => {
      const nativeFunction = () => 42;
      const boxedValue = box(nativeFunction);
      const result = unbox(boxedValue, callerModule);

      assert.strictEqual(result, nativeFunction);
    });

    it("object -> object", () => {
      class MyClass {}
      const nativeObject = new MyClass();
      const boxedValue = box(nativeObject);
      const result = unbox(boxedValue, callerModule);

      assert.strictEqual(result, nativeObject);
    });

    it("undefined -> undefined", () => {
      const nativeUndefinedValue = undefined;
      const boxedValue = box(nativeUndefinedValue);
      const result = unbox(boxedValue, callerModule);

      assert.strictEqual(result, nativeUndefinedValue);
    });
  });

  describe("default", () => {
    it("unknown type -> pass through", () => {
      const pid = Type.pid("nonode@nohost", [0, 0, 1]);

      assert.deepStrictEqual(unbox(pid, callerModule), pid);
    });
  });
});

describe("Elixir_Hologram_JS", () => {
  describe("call/4", () => {
    const call = Elixir_Hologram_JS["call/4"];
    let moduleProxy;

    beforeEach(() => {
      delete globalThis.Elixir_CallTestModule;

      Interpreter.defineManuallyPortedFunction(
        "CallTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      moduleProxy = Interpreter.moduleProxy(Type.alias("CallTestModule"));
    });

    it("calls method on receiver with unboxed args and boxes result", () => {
      const mathHelpers = {add: (a, b) => a + b};
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

    it("preserves 'this' binding for methods that depend on it", () => {
      const container = document.createElement("div");
      container.id = "test-bind-target";
      document.body.appendChild(container);

      const result = call(
        box(document),
        Type.atom("getElementById"),
        Type.list([Type.bitstring("test-bind-target")]),
        Type.alias("CallTestModule"),
      );

      const valueKey = Type.encodeMapKey(Type.atom("value"));
      const ref = result.data[valueKey][1];

      assert.isTrue(Type.isReference(ref));
      assert.strictEqual(ERTS.nativeObjectRegistry.get(ref), container);

      const expected = Type.nativeValueStruct("object", ref);

      assert.deepStrictEqual(result, expected);

      container.remove();
    });

    it("returns a Task struct when JS method returns a Promise", () => {
      const httpClient = {fetchData: async () => 42};
      moduleProxy.__jsBindings__.set("HttpClient", httpClient);

      const result = call(
        Type.atom("HttpClient"),
        Type.atom("fetchData"),
        Type.list(),
        Type.alias("CallTestModule"),
      );

      const mfa = Type.tuple([
        Type.alias("Hologram.JS"),
        Type.atom("call"),
        Type.integer(3),
      ]);

      const refKey = Type.encodeMapKey(Type.atom("ref"));
      const ref = result.data[refKey][1];

      const expected = Type.taskStruct(mfa, ERTS.INIT_PID, ref);

      assert.deepStrictEqual(result, expected);
    });

    describe("receiverless (nil receiver)", () => {
      it("calls imported binding directly", () => {
        const myMultiply = (a, b) => a * b;
        moduleProxy.__jsBindings__.set("multiply", myMultiply);

        const result = call(
          Type.atom("nil"),
          Type.atom("multiply"),
          Type.list([Type.integer(3), Type.integer(7)]),
          Type.alias("CallTestModule"),
        );

        assert.deepStrictEqual(result, Type.integer(21));
      });

      it("falls back to global function", () => {
        globalThis.__testGlobalFn__ = (x) => x + 100;

        const result = call(
          Type.atom("nil"),
          Type.atom("__testGlobalFn__"),
          Type.list([Type.integer(5)]),
          Type.alias("CallTestModule"),
        );

        assert.deepStrictEqual(result, Type.integer(105));

        delete globalThis.__testGlobalFn__;
      });

      it("returns a Task struct when function returns a Promise", () => {
        const myAsyncDouble = async (x) => x * 2;
        moduleProxy.__jsBindings__.set("asyncDouble", myAsyncDouble);

        const result = call(
          Type.atom("nil"),
          Type.atom("asyncDouble"),
          Type.list([Type.integer(10)]),
          Type.alias("CallTestModule"),
        );

        const mfa = Type.tuple([
          Type.alias("Hologram.JS"),
          Type.atom("call"),
          Type.integer(3),
        ]);

        const refKey = Type.encodeMapKey(Type.atom("ref"));
        const ref = result.data[refKey][1];

        const expected = Type.taskStruct(mfa, ERTS.INIT_PID, ref);

        assert.deepStrictEqual(result, expected);
      });
    });
  });

  describe("delete/3", () => {
    const deleteFn = Elixir_Hologram_JS["delete/3"];

    beforeEach(() => {
      delete globalThis.Elixir_DeleteTestModule;
    });

    it("deletes property from receiver", () => {
      class Settings {
        static theme = "light";
        static lang = "en";
      }

      Interpreter.defineManuallyPortedFunction(
        "DeleteTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(
        Type.alias("DeleteTestModule"),
      );

      moduleProxy.__jsBindings__.set("AppSettings", Settings);

      deleteFn(
        Type.atom("AppSettings"),
        Type.atom("theme"),
        Type.alias("DeleteTestModule"),
      );

      assert.strictEqual(Settings.theme, undefined);
      assert.isFalse("theme" in Settings);
      assert.strictEqual(Settings.lang, "en");
    });

    it("returns the receiver", () => {
      class Settings {
        static theme = "light";
      }

      Interpreter.defineManuallyPortedFunction(
        "DeleteTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(
        Type.alias("DeleteTestModule"),
      );

      moduleProxy.__jsBindings__.set("AppSettings", Settings);

      const result = deleteFn(
        Type.atom("AppSettings"),
        Type.atom("theme"),
        Type.alias("DeleteTestModule"),
      );

      assert.deepStrictEqual(result, Type.atom("AppSettings"));
    });
  });

  describe("dispatch_event/5", () => {
    const dispatchEvent = Elixir_Hologram_JS["dispatch_event/5"];

    beforeEach(() => {
      delete globalThis.Elixir_DispatchEventTestModule;

      Interpreter.defineManuallyPortedFunction(
        "DispatchEventTestModule",
        "dummy/0",
        "public",
        () => {},
      );
    });

    it("dispatches CustomEvent on target with no opts", () => {
      const target = document.createElement("div");
      let dispatched = null;

      target.addEventListener("chart:update", (event) => {
        dispatched = event;
      });

      dispatchEvent(
        box(target),
        Type.atom("CustomEvent"),
        Type.bitstring("chart:update"),
        Type.map(),
        Type.alias("DispatchEventTestModule"),
      );

      assert.instanceOf(dispatched, CustomEvent);
      assert.strictEqual(dispatched.type, "chart:update");
      assert.isNull(dispatched.detail);
    });

    it("dispatches CustomEvent with detail opts", () => {
      const target = document.createElement("div");
      let dispatched = null;

      target.addEventListener("chart:update", (event) => {
        dispatched = event;
      });

      const opts = Type.map([
        [
          Type.atom("detail"),
          Type.map([[Type.atom("data"), Type.integer(42)]]),
        ],
      ]);

      dispatchEvent(
        box(target),
        Type.atom("CustomEvent"),
        Type.bitstring("chart:update"),
        opts,
        Type.alias("DispatchEventTestModule"),
      );

      assert.deepStrictEqual(dispatched.detail, {data: 42});
    });

    it("dispatches native Event type with opts", () => {
      const target = document.createElement("div");
      let dispatched = null;

      target.addEventListener("click", (event) => {
        dispatched = event;
      });

      const opts = Type.map([[Type.atom("bubbles"), Type.atom("true")]]);

      dispatchEvent(
        box(target),
        Type.atom("MouseEvent"),
        Type.bitstring("click"),
        opts,
        Type.alias("DispatchEventTestModule"),
      );

      assert.instanceOf(dispatched, MouseEvent);
      assert.isTrue(dispatched.bubbles);
    });

    it("resolves atom target to globalThis (e.g. :document)", () => {
      let dispatched = null;

      document.addEventListener("app:ready", (event) => {
        dispatched = event;
      });

      dispatchEvent(
        Type.atom("document"),
        Type.atom("CustomEvent"),
        Type.bitstring("app:ready"),
        Type.map(),
        Type.alias("DispatchEventTestModule"),
      );

      assert.strictEqual(dispatched.type, "app:ready");
    });

    it("returns boxed boolean result from dispatchEvent()", () => {
      const target = document.createElement("div");

      const result = dispatchEvent(
        box(target),
        Type.atom("CustomEvent"),
        Type.bitstring("test:event"),
        Type.map(),
        Type.alias("DispatchEventTestModule"),
      );

      assert.deepStrictEqual(result, Type.atom("true"));
    });

    it("returns boxed false when event is cancelled", () => {
      const target = document.createElement("div");

      target.addEventListener("test:cancel", (event) => {
        event.preventDefault();
      });

      const opts = Type.map([[Type.atom("cancelable"), Type.atom("true")]]);

      const result = dispatchEvent(
        box(target),
        Type.atom("CustomEvent"),
        Type.bitstring("test:cancel"),
        opts,
        Type.alias("DispatchEventTestModule"),
      );

      assert.deepStrictEqual(result, Type.atom("false"));
    });
  });

  describe("eval/1", () => {
    const evalFn = Elixir_Hologram_JS["eval/1"];

    it("evaluates expression and boxes the result", () => {
      const expression = Type.bitstring("1 + 2");

      assert.deepStrictEqual(evalFn(expression), Type.integer(3));
    });
  });

  describe("exec/1", () => {
    const exec = Elixir_Hologram_JS["exec/1"];

    it("delegates to Interpreter.evaluateJavaScriptCode() and boxes the result", () => {
      const code = Type.bitstring("return 1 + 2");

      assert.deepStrictEqual(exec(code), Type.integer(3));
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

    it("returns NativeValue struct for undefined properties", () => {
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

      const expected = Type.nativeValueStruct("undefined", Type.nil());

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("instanceof/3", () => {
    const instanceofFn = Elixir_Hologram_JS["instanceof/3"];

    beforeEach(() => {
      delete globalThis.Elixir_InstanceofTestModule;
    });

    it("returns true when value is an instance of the class", () => {
      class Calculator {}
      const instance = new Calculator();

      Interpreter.defineManuallyPortedFunction(
        "InstanceofTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(
        Type.alias("InstanceofTestModule"),
      );

      moduleProxy.__jsBindings__.set("Calc", Calculator);

      const result = instanceofFn(
        box(instance),
        Type.atom("Calc"),
        Type.alias("InstanceofTestModule"),
      );

      assert.deepStrictEqual(result, Type.atom("true"));
    });

    it("returns false when value is not an instance of the class", () => {
      class Calculator {}
      class Widget {}
      const instance = new Widget();

      Interpreter.defineManuallyPortedFunction(
        "InstanceofTestModule",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(
        Type.alias("InstanceofTestModule"),
      );

      moduleProxy.__jsBindings__.set("Calc", Calculator);

      const result = instanceofFn(
        box(instance),
        Type.atom("Calc"),
        Type.alias("InstanceofTestModule"),
      );

      assert.deepStrictEqual(result, Type.atom("false"));
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

      const valueKey = Type.encodeMapKey(Type.atom("value"));
      const ref = result.data[valueKey][1];

      assert.isTrue(Type.isReference(ref));

      const jsInstance = ERTS.nativeObjectRegistry.get(ref);
      assert.instanceOf(jsInstance, Calculator);
      assert.strictEqual(jsInstance.initial, 10);

      const expected = Type.nativeValueStruct("object", ref);

      assert.deepStrictEqual(result, expected);
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

      const valueKey = Type.encodeMapKey(Type.atom("value"));
      const ref = result.data[valueKey][1];

      assert.isTrue(Type.isReference(ref));

      const jsInstance = ERTS.nativeObjectRegistry.get(ref);
      assert.instanceOf(jsInstance, Widget);
      assert.strictEqual(jsInstance.opts, DefaultOpts);

      const expected = Type.nativeValueStruct("object", ref);

      assert.deepStrictEqual(result, expected);
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

    describe("Elixir primitives", () => {
      it("bitstring -> string", () => {
        const result = typeofFn(
          Type.bitstring("hello"),
          Type.alias("TypeofTestModule"),
        );

        assert.deepStrictEqual(result, Type.bitstring("string"));
      });

      it("float -> number", () => {
        const result = typeofFn(
          Type.float(3.14),
          Type.alias("TypeofTestModule"),
        );

        assert.deepStrictEqual(result, Type.bitstring("number"));
      });

      it("integer -> number", () => {
        const result = typeofFn(
          Type.integer(42),
          Type.alias("TypeofTestModule"),
        );

        assert.deepStrictEqual(result, Type.bitstring("number"));
      });
    });

    describe("atoms", () => {
      it("boolean true -> boolean", () => {
        const result = typeofFn(
          Type.atom("true"),
          Type.alias("TypeofTestModule"),
        );

        assert.deepStrictEqual(result, Type.bitstring("boolean"));
      });

      it("boolean false -> boolean", () => {
        const result = typeofFn(
          Type.atom("false"),
          Type.alias("TypeofTestModule"),
        );

        assert.deepStrictEqual(result, Type.bitstring("boolean"));
      });

      it("nil -> object", () => {
        const result = typeofFn(
          Type.atom("nil"),
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

    describe("native values (via NativeValue struct)", () => {
      it("bigint -> bigint", () => {
        const result = typeofFn(box(42n), Type.alias("TypeofTestModule"));

        assert.deepStrictEqual(result, Type.bitstring("bigint"));
      });

      it("undefined -> undefined", () => {
        const result = typeofFn(box(undefined), Type.alias("TypeofTestModule"));

        assert.deepStrictEqual(result, Type.bitstring("undefined"));
      });

      it("object -> object", () => {
        class MyClass {}
        const instance = new MyClass();

        const result = typeofFn(box(instance), Type.alias("TypeofTestModule"));

        assert.deepStrictEqual(result, Type.bitstring("object"));
      });

      it("function -> function", () => {
        const fn = () => 42;

        const result = typeofFn(box(fn), Type.alias("TypeofTestModule"));

        assert.deepStrictEqual(result, Type.bitstring("function"));
      });
    });
  });
});
