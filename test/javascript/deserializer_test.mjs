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
        const atom = Type.atom("abc");

        it("top-level", () => {
          const serialized = serialize(atom);

          assert.deepStrictEqual(deserialize(serialized), atom);
        });

        it("nested", () => {
          const term = {a: atom, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(atom, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), atom);
        });
      });

      describe("bitstring", () => {
        describe("binary", () => {
          const bitstring = Type.bitstring('a"bc');

          it("top-level", () => {
            const serialized = serialize(bitstring);

            assert.deepStrictEqual(deserialize(serialized), bitstring);
          });

          it("nested", () => {
            const term = {a: bitstring, b: 2};
            const serialized = serialize(term);

            assert.deepStrictEqual(deserialize(serialized), term);
          });

          it("not versioned", () => {
            const serialized = serialize(bitstring, true, false);

            assert.deepStrictEqual(deserialize(serialized, false), bitstring);
          });
        });

        describe("non-binary", () => {
          const bitstring = Type.bitstring([1, 0, 1, 0]);

          it("top-level", () => {
            const serialized = serialize(bitstring);

            assert.deepStrictEqual(deserialize(serialized), bitstring);
          });

          it("nested", () => {
            const term = {a: bitstring, b: 2};
            const serialized = serialize(term);

            assert.deepStrictEqual(deserialize(serialized), term);
          });

          it("not versioned", () => {
            const serialized = serialize(bitstring, true, false);

            assert.deepStrictEqual(deserialize(serialized, false), bitstring);
          });
        });
      });

      describe("float", () => {
        const float = Type.float(1.23);

        it("top-level", () => {
          const serialized = serialize(float);

          assert.deepStrictEqual(deserialize(serialized), float);
        });

        it("nested", () => {
          const term = {a: float, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(float, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), float);
        });
      });

      describe("integer", () => {
        const integer = Type.integer(123);

        it("top-level", () => {
          const serialized = serialize(integer);

          assert.deepStrictEqual(deserialize(serialized), integer);
        });

        it("nested", () => {
          const term = {a: integer, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(integer, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), integer);
        });
      });

      describe("map", () => {
        const map = Type.map([
          [Type.atom("x"), Type.integer(1)],
          [Type.bitstring("y"), Type.float(1.23)],
        ]);

        it("top-level", () => {
          const serialized = serialize(map);

          assert.deepStrictEqual(deserialize(serialized), map);
        });

        it("nested", () => {
          const term = {a: map, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(map, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), map);
        });
      });
    });
  });
});
