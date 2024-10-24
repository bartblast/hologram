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

      describe("pid", () => {
        const pid = Type.pid('my_node@my_"host', [0, 11, 222], "client");

        it("top-level", () => {
          const serialized = serialize(pid);

          assert.deepStrictEqual(deserialize(serialized), pid);
        });

        it("nested", () => {
          const term = {a: pid, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(pid, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), pid);
        });
      });

      describe("port", () => {
        const port = Type.port("0.11", "client");

        it("top-level", () => {
          const serialized = serialize(port);

          assert.deepStrictEqual(deserialize(serialized), port);
        });

        it("nested", () => {
          const term = {a: port, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(port, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), port);
        });
      });

      describe("reference", () => {
        const reference = Type.reference("0.1.2.3", "client");

        it("top-level", () => {
          const serialized = serialize(reference);

          assert.deepStrictEqual(deserialize(serialized), reference);
        });

        it("nested", () => {
          const term = {a: reference, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(reference, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), reference);
        });
      });
    });

    describe("JS terms", () => {
      describe("array", () => {
        const array = [123, Type.float(2.34), Type.bitstring([1, 0, 1, 0])];

        it("top-level", () => {
          const serialized = serialize(array);

          assert.deepStrictEqual(deserialize(serialized), array);
        });

        it("nested", () => {
          const term = {a: array, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(array, true, false);

          assert.deepStrictEqual(deserialize(serialized, false), array);
        });
      });

      describe("BigInt", () => {
        const bigint = 123n;

        it("top-level", () => {
          const serialized = serialize(bigint);

          assert.equal(deserialize(serialized), bigint);
        });

        it("nested", () => {
          const term = {a: bigint, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(bigint, true, false);

          assert.equal(deserialize(serialized, false), bigint);
        });
      });

      describe("boolean", () => {
        const boolean = true;

        it("top-level", () => {
          const serialized = serialize(boolean);

          assert.equal(deserialize(serialized), boolean);
        });

        it("nested", () => {
          const term = {a: boolean, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(boolean, true, false);

          assert.equal(deserialize(serialized, false), boolean);
        });
      });

      describe("float", () => {
        const float = 1.23;

        it("top-level", () => {
          const serialized = serialize(float);

          assert.equal(deserialize(serialized), float);
        });

        it("nested", () => {
          const term = {a: float, b: 2};
          const serialized = serialize(term);

          assert.deepStrictEqual(deserialize(serialized), term);
        });

        it("not versioned", () => {
          const serialized = serialize(float, true, false);

          assert.equal(deserialize(serialized, false), float);
        });
      });
    });
  });
});
