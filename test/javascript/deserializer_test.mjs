"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Deserializer from "../../assets/js/deserializer.mjs";
import JsonEncoder from "../../assets/js/json_encoder.mjs";

defineGlobalErlangAndElixirModules();

describe("Deserializer", () => {
  describe("deserialize()", () => {
    it("string", () => {
      const obj = {a: 1, b: 2};
      const data = JsonEncoder.encode(obj);
      const result = Deserializer.deserialize(data);

      assert.deepStrictEqual(result, obj);
    });
  });
});
