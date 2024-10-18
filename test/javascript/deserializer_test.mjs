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

      describe("bitstring", () => {
        describe("binary", () => {
          it("top-level", () => {
            const term = Type.bitstring('a"bc');
            const serialized = serialize(term);

            assert.deepStrictEqual(deserialize(serialized), term);
          });

          it("nested", () => {
            const term = {a: Type.bitstring('a"bc'), b: 2};
            const serialized = serialize(term);

            assert.deepStrictEqual(deserialize(serialized), term);
          });

          it("not versioned", () => {
            const term = Type.bitstring('a"bc');
            const serialized = serialize(term, true, false);

            assert.deepStrictEqual(deserialize(serialized, false), term);
          });
        });

        describe("non-binary", () => {
          it("top-level", () => {
            const term = Type.bitstring([1, 0, 1, 0]);
            const serialized = serialize(term);

            assert.deepStrictEqual(deserialize(serialized), term);
          });

          it("nested", () => {
            const term = {a: Type.bitstring([1, 0, 1, 0]), b: 2};
            const serialized = serialize(term);

            assert.deepStrictEqual(deserialize(serialized), term);
          });

          it("not versioned", () => {
            const term = Type.bitstring([1, 0, 1, 0]);
            const serialized = serialize(term, true, false);

            assert.deepStrictEqual(deserialize(serialized, false), term);
          });
        });
      });

      describe("float", () => {
        it("top-level", () => {
          const term = Type.float(1.23);
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("nested", () => {
          const term = {a: Type.float(1.23), b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const term = Type.float(1.23);
          const serialized = serialize(term, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), term);
        });
      });

      describe("integer", () => {
        it("top-level", () => {
          const term = Type.integer(123);
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("nested", () => {
          const term = {a: Type.integer(123), b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const term = Type.integer(123);
          const serialized = serialize(term, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), term);
        });
      });

      describe("map", () => {
        it("top-level", () => {
          const term = Type.map([
            [Type.atom("x"), Type.integer(1)],
            [Type.bitstring("y"), Type.float(1.23)],
          ]);

          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("nested", () => {
          const term = {
            a: Type.map([
              [Type.atom("x"), Type.integer(1)],
              [Type.bitstring("y"), Type.float(1.23)],
            ]),
            b: 2,
          };

          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const term = Type.map([
            [Type.atom("x"), Type.integer(1)],
            [Type.bitstring("y"), Type.float(1.23)],
          ]);

          const serialized = serialize(term, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), term);
        });
      });
    });
  });
});
