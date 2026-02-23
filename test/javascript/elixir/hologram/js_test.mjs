"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Elixir_Hologram_JS, {
  box,
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
      delete globalThis.Elixir_TestModule1;
      delete globalThis.Elixir_TestModule2;
      delete globalThis.__testObj__;
    });

    it("resolves receiver from module's JS bindings", () => {
      const $1 = {add: (a, b) => a + b};

      Interpreter.defineManuallyPortedFunction(
        "TestModule1",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("TestModule1"));
      moduleProxy.__jsBindings__.set("MyLib", $1);

      const result = call(
        Type.alias("TestModule1"),
        Type.atom("MyLib"),
        Type.bitstring("add"),
        Type.list([Type.integer(2), Type.integer(3)]),
      );

      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("falls back to globalThis when not in bindings", () => {
      globalThis.__testObj__ = {greet: (name) => `hello ${name}`};

      Interpreter.defineManuallyPortedFunction(
        "TestModule2",
        "dummy/0",
        "public",
        () => {},
      );

      const result = call(
        Type.alias("TestModule2"),
        Type.atom("__testObj__"),
        Type.bitstring("greet"),
        Type.list([Type.bitstring("world")]),
      );

      assert.deepStrictEqual(result, Type.bitstring("hello world"));
    });

    it("resolves native receiver directly", () => {
      const obj = {getValue: () => 42};
      const nativeReceiver = {type: "native", value: obj};

      const result = call(
        Type.alias("Unused"),
        nativeReceiver,
        Type.bitstring("getValue"),
        Type.list(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
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
      delete globalThis.Elixir_TestModule5;
      delete globalThis.Elixir_TestModule6;
      delete globalThis.__testObj__;
    });

    it("resolves receiver from module's JS bindings", () => {
      class MyClass {
        static version = 3;
      }

      Interpreter.defineManuallyPortedFunction(
        "TestModule5",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("TestModule5"));
      moduleProxy.__jsBindings__.set("MyBoundClass", MyClass);

      const result = get(
        Type.alias("TestModule5"),
        Type.atom("MyBoundClass"),
        Type.atom("version"),
      );

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("falls back to globalThis when not in bindings", () => {
      globalThis.__testObj__ = {x: 42};

      Interpreter.defineManuallyPortedFunction(
        "TestModule6",
        "dummy/0",
        "public",
        () => {},
      );

      const result = get(
        Type.alias("TestModule6"),
        Type.atom("__testObj__"),
        Type.atom("x"),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("resolves native receiver directly", () => {
      const obj = {color: "red"};
      const nativeReceiver = {type: "native", value: obj};

      const result = get(
        Type.alias("Unused"),
        nativeReceiver,
        Type.atom("color"),
      );

      assert.deepStrictEqual(result, Type.bitstring("red"));
    });

    it("returns nil for undefined properties", () => {
      const obj = {a: 1};
      const nativeReceiver = {type: "native", value: obj};

      const result = get(
        Type.alias("Unused"),
        nativeReceiver,
        Type.atom("missing"),
      );

      assert.deepStrictEqual(result, Type.atom("nil"));
    });
  });

  describe("new/3", () => {
    const new3 = Elixir_Hologram_JS["new/3"];

    beforeEach(() => {
      delete globalThis.Elixir_TestModule3;
      delete globalThis.Elixir_TestModule4;
      delete globalThis.__TestClass__;
    });

    it("resolves class from module's JS bindings", () => {
      class MyClass {
        constructor(value) {
          this.initial = value;
        }
      }

      Interpreter.defineManuallyPortedFunction(
        "TestModule3",
        "dummy/0",
        "public",
        () => {},
      );

      const moduleProxy = Interpreter.moduleProxy(Type.alias("TestModule3"));
      moduleProxy.__jsBindings__.set("MyBoundClass", MyClass);

      const result = new3(
        Type.alias("TestModule3"),
        Type.atom("MyBoundClass"),
        Type.list([Type.integer(10)]),
      );

      assert.strictEqual(result.type, "native");
      assert.isTrue(result.value instanceof MyClass);
      assert.strictEqual(result.value.initial, 10);
    });

    it("falls back to globalThis when not in bindings", () => {
      globalThis.__TestClass__ = class {
        constructor(value) {
          this.initial = value;
        }
      };

      Interpreter.defineManuallyPortedFunction(
        "TestModule4",
        "dummy/0",
        "public",
        () => {},
      );

      const result = new3(
        Type.alias("TestModule4"),
        Type.atom("__TestClass__"),
        Type.list([Type.integer(10)]),
      );

      assert.strictEqual(result.type, "native");
      assert.isTrue(result.value instanceof globalThis.__TestClass__);
      assert.strictEqual(result.value.initial, 10);
    });

    it("resolves native class reference directly", () => {
      class Direct {
        constructor(value) {
          this.initial = value;
        }
      }

      const nativeClass = {type: "native", value: Direct};

      const result = new3(
        Type.alias("Unused"),
        nativeClass,
        Type.list([Type.integer(10)]),
      );

      assert.strictEqual(result.type, "native");
      assert.isTrue(result.value instanceof Direct);
      assert.strictEqual(result.value.initial, 10);
    });
  });
});
