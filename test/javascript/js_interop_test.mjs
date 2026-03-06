"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import JsInterop from "../../assets/js/js_interop.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("JsInterop", () => {
  describe("boxActionParam()", () => {
    describe("delegates to box() for leaf values", () => {
      it("null -> nil", () => {
        const result = JsInterop.boxActionParam(null);
        const expected = Type.atom("nil");

        assert.deepStrictEqual(result, expected);
      });

      it("undefined -> native", () => {
        const result = JsInterop.boxActionParam(undefined);
        const expected = {type: "native", value: undefined};

        assert.deepStrictEqual(result, expected);
      });

      it("true -> atom true", () => {
        const result = JsInterop.boxActionParam(true);
        const expected = Type.atom("true");

        assert.deepStrictEqual(result, expected);
      });

      it("false -> atom false", () => {
        const result = JsInterop.boxActionParam(false);
        const expected = Type.atom("false");

        assert.deepStrictEqual(result, expected);
      });

      it("bigint -> native", () => {
        const result = JsInterop.boxActionParam(42n);
        const expected = {type: "native", value: 42n};

        assert.deepStrictEqual(result, expected);
      });

      it("integer -> integer", () => {
        const result = JsInterop.boxActionParam(42);
        const expected = Type.integer(42);

        assert.deepStrictEqual(result, expected);
      });

      it("negative integer -> integer", () => {
        const result = JsInterop.boxActionParam(-42);
        const expected = Type.integer(-42);

        assert.deepStrictEqual(result, expected);
      });

      it("float -> float", () => {
        const result = JsInterop.boxActionParam(3.14);
        const expected = Type.float(3.14);

        assert.deepStrictEqual(result, expected);
      });

      it("negative float -> float", () => {
        const result = JsInterop.boxActionParam(-3.14);
        const expected = Type.float(-3.14);

        assert.deepStrictEqual(result, expected);
      });

      it("0 -> integer", () => {
        const result = JsInterop.boxActionParam(0);
        const expected = Type.integer(0);

        assert.deepStrictEqual(result, expected);
      });

      it("0.0 -> integer", () => {
        const result = JsInterop.boxActionParam(0.0);
        const expected = Type.integer(0);

        assert.deepStrictEqual(result, expected);
      });

      it("+0.0 -> integer", () => {
        const result = JsInterop.boxActionParam(+0.0);
        const expected = Type.integer(0);

        assert.deepStrictEqual(result, expected);
      });

      it("-0.0 -> integer", () => {
        const result = JsInterop.boxActionParam(-0.0);
        const expected = Type.integer(0);

        assert.deepStrictEqual(result, expected);
      });

      it("string -> bitstring", () => {
        const result = JsInterop.boxActionParam("hello");
        const expected = Type.bitstring("hello");

        assert.deepStrictEqual(result, expected);
      });

      it("empty string -> bitstring", () => {
        const result = JsInterop.boxActionParam("");
        const expected = Type.bitstring("");

        assert.deepStrictEqual(result, expected);
      });

      it("function -> native", () => {
        const fn = () => 42;

        const result = JsInterop.boxActionParam(fn);
        const expected = {type: "native", value: fn};

        assert.deepStrictEqual(result, expected);
      });

      it("class instance -> native", () => {
        class MyClass {}
        const instance = new MyClass();

        const result = JsInterop.boxActionParam(instance);
        const expected = {type: "native", value: instance};

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("plain objects use atom keys", () => {
      it("plain object -> map with atom keys", () => {
        const result = JsInterop.boxActionParam({a: 1, b: "hello"});

        const expected = Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.bitstring("hello")],
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("empty object -> empty map", () => {
        const result = JsInterop.boxActionParam({});
        const expected = Type.map();

        assert.deepStrictEqual(result, expected);
      });

      it("null prototype object -> map with atom keys", () => {
        const obj = Object.create(null);
        obj.a = 1;

        const result = JsInterop.boxActionParam(obj);
        const expected = Type.map([[Type.atom("a"), Type.integer(1)]]);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("arrays recurse through boxActionParam", () => {
      it("array -> list", () => {
        const result = JsInterop.boxActionParam([1, "two", true]);

        const expected = Type.list([
          Type.integer(1),
          Type.bitstring("two"),
          Type.boolean(true),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("empty array -> empty list", () => {
        const result = JsInterop.boxActionParam([]);
        const expected = Type.list();

        assert.deepStrictEqual(result, expected);
      });

      it("nested arrays -> nested lists", () => {
        const result = JsInterop.boxActionParam([[1, 2], [3]]);

        const expected = Type.list([
          Type.list([Type.integer(1), Type.integer(2)]),
          Type.list([Type.integer(3)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("nested data structures use atom keys at every level", () => {
      it("nested objects -> nested maps with atom keys", () => {
        const result = JsInterop.boxActionParam({a: {b: 1}});

        const expected = Type.map([
          [Type.atom("a"), Type.map([[Type.atom("b"), Type.integer(1)]])],
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("object inside array -> map with atom keys", () => {
        const result = JsInterop.boxActionParam([{a: 1}, {b: 2}]);

        const expected = Type.list([
          Type.map([[Type.atom("a"), Type.integer(1)]]),
          Type.map([[Type.atom("b"), Type.integer(2)]]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("array inside object -> list with atom-keyed maps", () => {
        const result = JsInterop.boxActionParam({items: [{id: 1}, {id: 2}]});

        const expected = Type.map([
          [
            Type.atom("items"),
            Type.list([
              Type.map([[Type.atom("id"), Type.integer(1)]]),
              Type.map([[Type.atom("id"), Type.integer(2)]]),
            ]),
          ],
        ]);

        assert.deepStrictEqual(result, expected);
      });
    });
  });
});
