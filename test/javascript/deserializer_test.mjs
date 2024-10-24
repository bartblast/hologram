"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Deserializer from "../../assets/js/deserializer.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const deserialize = Deserializer.deserialize;
const serialize = Serializer.serialize;

function testNestedDeserialization(nestedTerm) {
  const term = {a: nestedTerm, b: 2};
  const serialized = serialize(term);
  const deserialized = deserialize(serialized);

  assert.deepStrictEqual(deserialized, term);
}

function testNotVersionedDeserialization(term) {
  const serialized = serialize(term, true, false);
  const deserialized = deserialize(serialized, false);

  assert.deepStrictEqual(deserialized, term);
}

function testTopLevelDeserialization(term) {
  const serialized = serialize(term);
  const deserialized = deserialize(serialized);

  assert.deepStrictEqual(deserialized, term);
}

describe("Deserializer", () => {
  describe("deserialize()", () => {
    describe("boxed terms", () => {
      describe("atom", () => {
        const term = Type.atom("abc");

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("bitstring", () => {
        describe("binary", () => {
          const term = Type.bitstring('a"bc');

          it("top-level", () => {
            testTopLevelDeserialization(term);
          });

          it("nested", () => {
            testNestedDeserialization(term);
          });

          it("not versioned", () => {
            testNotVersionedDeserialization(term);
          });
        });

        describe("non-binary", () => {
          const term = Type.bitstring([1, 0, 1, 0]);

          it("top-level", () => {
            testTopLevelDeserialization(term);
          });

          it("nested", () => {
            testNestedDeserialization(term);
          });

          it("not versioned", () => {
            testNotVersionedDeserialization(term);
          });
        });
      });

      describe("float", () => {
        const term = Type.float(1.23);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("integer", () => {
        const term = Type.integer(123);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("map", () => {
        const term = Type.map([
          [Type.atom("x"), Type.integer(1)],
          [Type.bitstring("y"), Type.float(1.23)],
        ]);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("pid", () => {
        const term = Type.pid('my_node@my_"host', [0, 11, 222], "client");

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("port", () => {
        const term = Type.port("0.11", "client");

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("reference", () => {
        const term = Type.reference("0.1.2.3", "client");

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });
    });

    describe("JS terms", () => {
      describe("array", () => {
        const term = [123, Type.float(2.34), Type.bitstring([1, 0, 1, 0])];

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("BigInt", () => {
        const term = 123n;

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("boolean", () => {
        const term = true;

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("float", () => {
        const term = 1.23;

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("function", () => {
        describe("longhand syntax", () => {
          const fun = function (a, b) {
            const result = Type.integer(a + b);
            return result;
          };

          it("top-level", () => {
            const serialized = serialize(fun);
            const result = deserialize(serialized);

            assert.isFunction(result);
            assert.deepStrictEqual(result(1, 2), Type.integer(3));
          });

          it("nested", () => {
            const term = {a: fun, b: 2};
            const serialized = serialize(term);
            const result = deserialize(serialized);

            assert.isFunction(result.a);
            assert.deepStrictEqual(result.a(1, 2), Type.integer(3));
            assert.deepStrictEqual(result, {a: result.a, b: 2});
          });

          it("not versioned", () => {
            const serialized = serialize(fun, true, false);
            const result = deserialize(serialized, false);

            assert.isFunction(result);
            assert.deepStrictEqual(result(1, 2), Type.integer(3));
          });
        });

        describe("shorthand syntax", () => {
          const fun = (a, b) => Type.integer(a + b);

          it("top-level", () => {
            const serialized = serialize(fun);
            const result = deserialize(serialized);

            assert.isFunction(result);
            assert.deepStrictEqual(result(1, 2), Type.integer(3));
          });

          it("nested", () => {
            const term = {a: fun, b: 2};
            const serialized = serialize(term);
            const result = deserialize(serialized);

            assert.isFunction(result.a);
            assert.deepStrictEqual(result.a(1, 2), Type.integer(3));
            assert.deepStrictEqual(result, {a: result.a, b: 2});
          });

          it("not versioned", () => {
            const serialized = serialize(fun, true, false);
            const result = deserialize(serialized, false);

            assert.isFunction(result);
            assert.deepStrictEqual(result(1, 2), Type.integer(3));
          });
        });
      });

      describe("integer", () => {
        const term = 123;

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });

      describe("null", () => {
        const term = null;

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });

        it("not versioned", () => {
          testNotVersionedDeserialization(term);
        });
      });
    });
  });
});
