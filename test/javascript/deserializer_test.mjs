"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Deserializer from "../../assets/js/deserializer.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Deserializer", () => {
  describe("deserialize()", () => {
    const deserialize = Deserializer.deserialize;
    const serialize = Serializer.serialize;

    describe("boxed terms", () => {
      describe("atom", () => {
        it("top-level", () => {
          const term = Type.atom("abc");
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("nested", () => {
          const term = {a: Type.atom("abc"), b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const term = Type.atom("abc");
          const serialized = serialize(term, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), term);
        });
      });
    });
  });
});
