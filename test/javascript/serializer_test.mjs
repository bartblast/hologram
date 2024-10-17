"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Serializer from "../../assets/js/serializer.mjs";

defineGlobalErlangAndElixirModules();

describe("Serializer", () => {
  describe("serialize()", () => {
    const serialize = Serializer.serialize;

    it("JS BigInt", () => {
      const term = 123n;
      const expected = "__bigint__:123";

      assert.equal(serialize(term), expected);
    });

    it("JS BigInt nested in object", () => {
      const term = {a: 123n, b: 2};
      const expected = '{"a":"__bigint__:123","b":2}';

      assert.equal(serialize(term), expected);
    });
  });
});
