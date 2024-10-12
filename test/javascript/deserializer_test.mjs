"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Deserializer from "../../assets/js/deserializer.mjs";
import JsonEncoder from "../../assets/js/json_encoder.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Deserializer", () => {
  describe("deserialize()", () => {
    it("JS object", () => {
      const obj = {a: 1, b: 2};
      const data = JsonEncoder.encode(obj);
      const result = Deserializer.deserialize(data);

      assert.deepStrictEqual(result, obj);
    });

    it("boxed bitstring that is a binary", () => {
      const term = Type.bitstring("abc");
      const data = JsonEncoder.encode(term);
      const result = Deserializer.deserialize(data);

      assert.deepStrictEqual(result, term);
    });

    it("boxed integer", () => {
      const term = Type.integer(123);
      const data = JsonEncoder.encode(term);
      const result = Deserializer.deserialize(data);

      assert.deepStrictEqual(result, term);
    });

    it("boxed nil", () => {
      const term = Type.nil();
      const data = JsonEncoder.encode(term);
      const result = Deserializer.deserialize(data);

      assert.deepStrictEqual(result, term);
    });
  });
});
