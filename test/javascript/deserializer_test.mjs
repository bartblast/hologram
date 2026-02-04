"use strict";

import {
  assert,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Deserializer from "../../assets/js/deserializer.mjs";
import ERTS from "../../assets/js/erts.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const deserialize = Deserializer.deserialize;
const serialize = Serializer.serialize;

function testNestedBitstringDeserialization(
  nestedTerm,
  destination = "server",
) {
  const term = {x: nestedTerm};
  const serialized = serialize(term, destination);
  const deserialized = deserialize(serialized);

  assert.equal(typeof deserialized, "object");
  assert.deepStrictEqual(Object.keys(deserialized), ["x"]);
  assert.isTrue(Type.isBitstring(deserialized.x));
  assert.isTrue(Interpreter.isStrictlyEqual(deserialized.x, term.x));
}

function testNestedDeserialization(
  nestedTerm,
  destination = "server",
  expectedNestedTerm = null,
) {
  const term = {x: nestedTerm};
  const serialized = serialize(term, destination);
  const deserialized = deserialize(serialized);

  let expected;

  if (expectedNestedTerm === null) {
    expected = term;
  } else {
    expected = {x: expectedNestedTerm};
  }

  assert.deepStrictEqual(deserialized, expected);
}

function testTopLevelBitstringDeserialization(term, destination = "server") {
  const serialized = serialize(term, destination);
  const deserialized = deserialize(serialized);

  assert.isTrue(Interpreter.isStrictlyEqual(deserialized, term));
}

function testTopLevelDeserialization(
  term,
  destination = "server",
  expected = null,
) {
  const serialized = serialize(term, destination);
  const deserialized = deserialize(serialized);

  if (expected === null) {
    expected = term;
  }

  assert.deepStrictEqual(deserialized, expected);
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
      });

      describe("bitstring", () => {
        describe("empty", () => {
          const term = Type.bitstring("");

          it("top-level", () => {
            testTopLevelBitstringDeserialization(term);
          });

          it("nested", () => {
            testNestedBitstringDeserialization(term);
          });
        });

        describe("single-byte", () => {
          describe("without leftover bits", () => {
            const term = Type.bitstring("a");

            it("top-level", () => {
              testTopLevelBitstringDeserialization(term);
            });

            it("nested", () => {
              testNestedBitstringDeserialization(term);
            });
          });

          describe("with leftover bits", () => {
            const term = Type.bitstring([1, 0, 1, 0]);

            it("top-level", () => {
              testTopLevelBitstringDeserialization(term);
            });

            it("nested", () => {
              testNestedBitstringDeserialization(term);
            });
          });
        });

        describe("multiple-byte", () => {
          describe("without leftover bits", () => {
            const term = Type.bitstring("Hologram");

            it("top-level", () => {
              testTopLevelBitstringDeserialization(term);
            });

            it("nested", () => {
              testNestedBitstringDeserialization(term);
            });
          });

          describe("with leftover bits", () => {
            const term = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]);

            it("top-level", () => {
              testTopLevelBitstringDeserialization(term);
            });

            it("nested", () => {
              testNestedBitstringDeserialization(term);
            });
          });
        });
      });

      describe("float", () => {
        describe("encoded as float", () => {
          const term = Type.float(1.23);

          it("top-level", () => {
            testTopLevelDeserialization(term);
          });

          it("nested", () => {
            testNestedDeserialization(term);
          });
        });

        describe("encoded as integer", () => {
          const term = Type.float(123);

          it("top-level", () => {
            testTopLevelDeserialization(term);
          });

          it("nested", () => {
            testNestedDeserialization(term);
          });
        });
      });

      describe("function", () => {
        beforeEach(() => {
          ERTS.funSequence.reset();
        });

        const context = contextFixture({
          module: Type.alias("MyModule"),
          vars: {x: Type.integer(10), y: Type.integer(20)},
        });

        describe("capture", () => {
          const term = Type.functionCapture(
            "Calendar.ISO",
            "date_to_string",
            4,
            [],
            context,
          );

          const expectedContext = contextFixture({
            module: null,
            vars: {},
          });

          const expectedTerm = {...term, context: expectedContext};

          it("top-level", () => {
            testTopLevelDeserialization(term, "server", expectedTerm);
          });

          it("nested", () => {
            testNestedDeserialization(term, "server", expectedTerm);
          });
        });

        describe("non-capture", () => {
          const term = Type.anonymousFunction(
            1,
            [
              {
                params: (_context) => [Type.variablePattern("a")],
                guards: [
                  (context) => Erlang["/=/2"](context.vars.a, Type.integer(1)),
                ],
                // prettier-ignore
                body: (context) => { return Type.list([Type.atom("m"), context.vars.a, context.vars.x]) },
              },
              {
                params: (_context) => [Type.variablePattern("a")],
                guards: [
                  (context) => Erlang["/=/2"](context.vars.a, Type.integer(2)),
                ],
                // prettier-ignore
                body: (context) => { return Type.list([Type.atom("n"), context.vars.a, context.vars.y]) },
              },
            ],
            context,
          );

          it("top-level", () => {
            const serialized = serialize(term, "client");
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
              Type.atom("n"),
              Type.integer(1),
              Type.integer(20),
            ]);

            assert.deepStrictEqual(callResult, expectedCallResult);
          });

          it("nested", () => {
            const nestedTerm = {t: term};
            const serialized = serialize(nestedTerm, "client");
            const deserialized = deserialize(serialized);

            assert.deepStrictEqual(deserialized, {
              t: {
                ...term,
                clauses: deserialized.t.clauses,
              },
            });

            assert.equal(deserialized.t.clauses.length, 2);

            assert.isFunction(deserialized.t.clauses[0].params);
            assert.isFunction(deserialized.t.clauses[0].guards[0]);
            assert.isFunction(deserialized.t.clauses[0].body);

            assert.isFunction(deserialized.t.clauses[1].params);
            assert.isFunction(deserialized.t.clauses[1].guards[0]);
            assert.isFunction(deserialized.t.clauses[1].body);

            const callResult = Interpreter.callAnonymousFunction(
              deserialized.t,
              [Type.integer(1)],
            );

            const expectedCallResult = Type.list([
              Type.atom("n"),
              Type.integer(1),
              Type.integer(20),
            ]);

            assert.deepStrictEqual(callResult, expectedCallResult);
          });
        });
      });

      describe("integer", () => {
        const term = Type.integer(90071992547409919007199254740991n);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });

      describe("list", () => {
        const term = Type.list([Type.integer(1), Type.float(2.34)]);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });

      describe("map", () => {
        const term = Type.map([
          [Type.atom("x"), Type.integer(1)],
          [Type.atom("y"), Type.float(2.34)],
        ]);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });

      describe("pid", () => {
        const term = Type.pid('my_node@my_"host', [0, 11, 222], "server");

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });

      describe("port", () => {
        const term = Type.port('my_node@my_"host', [0, 11], "server");

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });

      describe("reference", () => {
        const term = Type.reference('my_node@my_"host', 0, [3, 2, 1]);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });

      describe("tuple", () => {
        const term = Type.tuple([Type.integer(1), Type.float(2.34)]);

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });
    });

    describe("JS terms", () => {
      describe("array", () => {
        const term = [9, 8.76];

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
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
      });

      describe("function", () => {
        describe("longhand syntax", () => {
          it("top-level", () => {
            const serialized = `[2,"ufunction (a, b) { const result = Type.integer(a + b); return result; }"]`;
            const deserialized = deserialize(serialized);

            assert.isFunction(deserialized);
            assert.deepStrictEqual(deserialized(1, 2), Type.integer(3));
          });

          it("nested", () => {
            const serialized = `[2,{"x":"ufunction (a, b) { const result = Type.integer(a + b); return result; }"}]`;
            const deserialized = deserialize(serialized);

            assert.deepStrictEqual(Object.keys(deserialized), ["x"]);
            assert.isFunction(deserialized.x);
            assert.deepStrictEqual(deserialized.x(1, 2), Type.integer(3));
          });
        });

        describe("shorthand syntax", () => {
          it("top-level", () => {
            const serialized = `[2,"u(a, b) => Type.integer(a + b)"]`;
            const deserialized = deserialize(serialized);

            assert.isFunction(deserialized);
            assert.deepStrictEqual(deserialized(1, 2), Type.integer(3));
          });

          it("nested", () => {
            const serialized = `[2,{"x":"u(a, b) => Type.integer(a + b)"}]`;
            const deserialized = deserialize(serialized);

            assert.deepStrictEqual(Object.keys(deserialized), ["x"]);
            assert.isFunction(deserialized.x);
            assert.deepStrictEqual(deserialized.x(1, 2), Type.integer(3));
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
      });

      describe("null", () => {
        const term = null;

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
        });
      });

      describe("object", () => {
        const term = {v: 9, 'x"yz': 8.76};

        it("top-level", () => {
          testTopLevelDeserialization(term);
        });

        it("nested", () => {
          testNestedDeserialization(term);
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
      });
    });
  });
});
