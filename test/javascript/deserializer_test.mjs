"use strict";

import {
  assert,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Deserializer from "../../assets/js/deserializer.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
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
      describe("anonymous_function", () => {
        const term = Type.anonymousFunction(
          1,
          [
            {
              params: (_context) => [Type.variablePattern("x")],
              guards: [
                (context) => Erlang["/=/2"](context.vars.x, Type.integer(1)),
              ],
              // prettier-ignore
              body: (context) => { return Type.list([Type.atom("a"), context.vars.x, context.vars.i]) },
            },
            {
              params: (_context) => [Type.variablePattern("x")],
              guards: [
                (context) => Erlang["/=/2"](context.vars.x, Type.integer(2)),
              ],
              // prettier-ignore
              body: (context) => { return Type.list([Type.atom("b"), context.vars.x, context.vars.j]) },
            },
          ],
          contextFixture({vars: {i: Type.integer(10), j: Type.integer(20)}}),
        );

        it("top-level", () => {
          const serialized = serialize(term);
          const deserialized = deserialize(serialized);

          assert.deepStrictEqual(deserialized, {
            ...term,
            clauses: deserialized.clauses,
          });

          assert.equal(deserialized.clauses.length, 2);

          assert.isFunction(deserialized.clauses[0].params);
          assert.isFunction(deserialized.clauses[0].guards[0]);
          assert.isFunction(deserialized.clauses[0].body);

          assert.isFunction(deserialized.clauses[1].params);
          assert.isFunction(deserialized.clauses[1].guards[0]);
          assert.isFunction(deserialized.clauses[1].body);

          const callResult = Interpreter.callAnonymousFunction(deserialized, [
            Type.integer(1),
          ]);

          const expectedCallResult = Type.list([
            Type.atom("b"),
            Type.integer(1),
            Type.integer(20),
          ]);

          assert.deepStrictEqual(callResult, expectedCallResult);
        });

        it("nested", () => {
          const nestedTerm = {a: term, b: 2};
          const serialized = serialize(nestedTerm);
          const deserialized = deserialize(serialized);

          assert.deepStrictEqual(deserialized, {
            a: {
              ...term,
              clauses: deserialized.a.clauses,
            },
            b: 2,
          });

          assert.equal(deserialized.a.clauses.length, 2);

          assert.isFunction(deserialized.a.clauses[0].params);
          assert.isFunction(deserialized.a.clauses[0].guards[0]);
          assert.isFunction(deserialized.a.clauses[0].body);

          assert.isFunction(deserialized.a.clauses[1].params);
          assert.isFunction(deserialized.a.clauses[1].guards[0]);
          assert.isFunction(deserialized.a.clauses[1].body);

          const callResult = Interpreter.callAnonymousFunction(deserialized.a, [
            Type.integer(1),
          ]);

          const expectedCallResult = Type.list([
            Type.atom("b"),
            Type.integer(1),
            Type.integer(20),
          ]);

          assert.deepStrictEqual(callResult, expectedCallResult);
        });

        it("not versioned", () => {
          const serialized = serialize(term, true, false);
          const deserialized = deserialize(serialized, false);

          assert.deepStrictEqual(deserialized, {
            ...term,
            clauses: deserialized.clauses,
          });

          assert.equal(deserialized.clauses.length, 2);

          assert.isFunction(deserialized.clauses[0].params);
          assert.isFunction(deserialized.clauses[0].guards[0]);
          assert.isFunction(deserialized.clauses[0].body);

          assert.isFunction(deserialized.clauses[1].params);
          assert.isFunction(deserialized.clauses[1].guards[0]);
          assert.isFunction(deserialized.clauses[1].body);

          const callResult = Interpreter.callAnonymousFunction(deserialized, [
            Type.integer(1),
          ]);

          const expectedCallResult = Type.list([
            Type.atom("b"),
            Type.integer(1),
            Type.integer(20),
          ]);

          assert.deepStrictEqual(callResult, expectedCallResult);
        });
      });

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

      describe("list", () => {
        const term = Type.list([Type.integer(1), Type.float(1.23)]);

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

      describe("tuple", () => {
        const term = Type.tuple([Type.integer(1), Type.float(1.23)]);

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
            const deserialized = deserialize(serialized);

            assert.isFunction(deserialized);
            assert.deepStrictEqual(deserialized(1, 2), Type.integer(3));
          });

          it("nested", () => {
            const term = {a: fun, b: 2};
            const serialized = serialize(term);
            const deserialized = deserialize(serialized);

            assert.isFunction(deserialized.a);
            assert.deepStrictEqual(deserialized.a(1, 2), Type.integer(3));
            assert.deepStrictEqual(deserialized, {a: deserialized.a, b: 2});
          });

          it("not versioned", () => {
            const serialized = serialize(fun, true, false);
            const deserialized = deserialize(serialized, false);

            assert.isFunction(deserialized);
            assert.deepStrictEqual(deserialized(1, 2), Type.integer(3));
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

      describe("object", () => {
        const term = {v: 6, 'x"yz': 9.87};

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

      describe("string", () => {
        const term = 'a"bc';

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
