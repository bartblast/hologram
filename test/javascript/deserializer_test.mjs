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
  const term = {x: nestedTerm, y: 2};
  const serialized = serialize(term);
  const deserialized = deserialize(serialized);

  assert.deepStrictEqual(deserialized, term);
}

function testNestedBitstringDeserialization(nestedTerm) {
  const term = {x: nestedTerm, y: 2};
  const serialized = serialize(term);
  const deserialized = deserialize(serialized);

  assert.equal(typeof deserialized, "object");
  assert.deepStrictEqual(Object.keys(deserialized), ["x", "y"]);
  assert.isTrue(Interpreter.isStrictlyEqual(deserialized.x, term.x));
}

function testNotVersionedDeserialization(term) {
  const serialized = serialize(term, true, false);
  const deserialized = deserialize(serialized, false);

  assert.deepStrictEqual(deserialized, term);
}

function testNotVersionedBitstringDeserialization(term) {
  const serialized = serialize(term, true, false);
  const deserialized = deserialize(serialized, false);

  assert.isTrue(Interpreter.isStrictlyEqual(deserialized, term));
}

function testTopLevelDeserialization(term) {
  const serialized = serialize(term);
  const deserialized = deserialize(serialized);

  assert.deepStrictEqual(deserialized, term);
}

function testTopLevelBitstringDeserialization(term) {
  const serialized = serialize(term);
  const deserialized = deserialize(serialized);

  assert.isTrue(Interpreter.isStrictlyEqual(deserialized, term));
}

describe.only("Deserializer", () => {
  describe("deserialize()", () => {
    describe("OVERHAUL: boxed terms", () => {
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
        const term = Type.integer(90071992547409919007199254740991n);

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
          [Type.atom("y"), Type.float(2.34)],
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
        const term = Type.tuple([Type.integer(1), Type.float(2.34)]);

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

    describe("OVERHAUL: JS terms", () => {
      describe("array", () => {
        const term = [123, Type.float(2.34), Type.atom("abc")];

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
            const term = {x: fun, y: 2};
            const serialized = serialize(term);
            const result = deserialize(serialized);

            assert.isFunction(result.x);
            assert.deepStrictEqual(result.x(1, 2), Type.integer(3));
            assert.deepStrictEqual(result, {x: result.x, y: 2});
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
            const term = {x: fun, y: 2};
            const serialized = serialize(term);
            const deserialized = deserialize(serialized);

            assert.isFunction(deserialized.x);
            assert.deepStrictEqual(deserialized.x(1, 2), Type.integer(3));
            assert.deepStrictEqual(deserialized, {x: deserialized.x, y: 2});
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

    describe("version 2 (current)", () => {
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
            const nestedTerm = {x: term, y: 2};
            const serialized = serialize(nestedTerm);
            const deserialized = deserialize(serialized);

            assert.deepStrictEqual(deserialized, {
              x: {
                ...term,
                clauses: deserialized.x.clauses,
              },
              y: 2,
            });

            assert.equal(deserialized.x.clauses.length, 2);

            assert.isFunction(deserialized.x.clauses[0].params);
            assert.isFunction(deserialized.x.clauses[0].guards[0]);
            assert.isFunction(deserialized.x.clauses[0].body);

            assert.isFunction(deserialized.x.clauses[1].params);
            assert.isFunction(deserialized.x.clauses[1].guards[0]);
            assert.isFunction(deserialized.x.clauses[1].body);

            const callResult = Interpreter.callAnonymousFunction(
              deserialized.x,
              [Type.integer(1)],
            );

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
          describe("empty", () => {
            const term = Type.bitstring2("");

            it("top-level", () => {
              testTopLevelBitstringDeserialization(term);
            });

            it("nested", () => {
              testNestedBitstringDeserialization(term);
            });

            it("not versioned", () => {
              testNotVersionedBitstringDeserialization(term);
            });
          });

          describe("single-byte", () => {
            describe("without leftover bits", () => {
              const term = Type.bitstring2("a");

              it("top-level", () => {
                testTopLevelBitstringDeserialization(term);
              });

              it("nested", () => {
                testNestedBitstringDeserialization(term);
              });

              it("not versioned", () => {
                testNotVersionedBitstringDeserialization(term);
              });
            });

            describe("with leftover bits", () => {
              const term = Type.bitstring2([1, 0, 1, 0]);

              it("top-level", () => {
                testTopLevelBitstringDeserialization(term);
              });

              it("nested", () => {
                testNestedBitstringDeserialization(term);
              });

              it("not versioned", () => {
                testNotVersionedBitstringDeserialization(term);
              });
            });
          });

          describe("multiple-byte", () => {
            describe("without leftover bits", () => {
              const term = Type.bitstring2("Hologram");

              it("top-level", () => {
                testTopLevelBitstringDeserialization(term);
              });

              it("nested", () => {
                testNestedBitstringDeserialization(term);
              });

              it("not versioned", () => {
                testNotVersionedBitstringDeserialization(term);
              });
            });

            describe("with leftover bits", () => {
              const term = Type.bitstring2([
                1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0,
              ]);

              it("top-level", () => {
                testTopLevelBitstringDeserialization(term);
              });

              it("nested", () => {
                testNestedBitstringDeserialization(term);
              });

              it("not versioned", () => {
                testNotVersionedBitstringDeserialization(term);
              });
            });
          });
        });
      });
    });

    describe("old versions", () => {
      describe("version 1", () => {
        describe("boxed terms", () => {
          describe("anonymous_function", () => {
            const term = Type.anonymousFunction(
              1,
              [
                {
                  params: (_context) => [Type.variablePattern("x")],
                  guards: [
                    (context) =>
                      Erlang["/=/2"](context.vars.x, Type.integer(1)),
                  ],
                  // prettier-ignore
                  body: (context) => { return Type.list([Type.atom("a"), context.vars.x, context.vars.i]) },
                },
                {
                  params: (_context) => [Type.variablePattern("x")],
                  guards: [
                    (context) =>
                      Erlang["/=/2"](context.vars.x, Type.integer(2)),
                  ],
                  // prettier-ignore
                  body: (context) => { return Type.list([Type.atom("b"), context.vars.x, context.vars.j]) },
                },
              ],
              contextFixture({
                vars: {i: Type.integer(10), j: Type.integer(20)},
              }),
            );

            it("top-level", () => {
              const serialized =
                '[1,{"type":"anonymous_function","arity":1,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":["__function__:(context) =>\\n                      Erlang[\\"/=/2\\"](context.vars.x, Type.integer(1))"],"body":"__function__:(context) => { return Type.list([Type.atom(\\"a\\"), context.vars.x, context.vars.i]) }"},{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":["__function__:(context) =>\\n                      Erlang[\\"/=/2\\"](context.vars.x, Type.integer(2))"],"body":"__function__:(context) => { return Type.list([Type.atom(\\"b\\"), context.vars.x, context.vars.j]) }"}],"context":{"module":"__atom__:Elixir.MyModule","vars":{"i":"__integer__:10","j":"__integer__:20"}},"uniqueId":2}]';
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

              const callResult = Interpreter.callAnonymousFunction(
                deserialized,
                [Type.integer(1)],
              );

              const expectedCallResult = Type.list([
                Type.atom("b"),
                Type.integer(1),
                Type.integer(20),
              ]);

              assert.deepStrictEqual(callResult, expectedCallResult);
            });

            it("nested", () => {
              // nestedTerm = {x: term, y: 2};
              const serialized =
                '[1,{"x":{"type":"anonymous_function","arity":1,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":["__function__:(context) =>\\n                      Erlang[\\"/=/2\\"](context.vars.x, Type.integer(1))"],"body":"__function__:(context) => { return Type.list([Type.atom(\\"a\\"), context.vars.x, context.vars.i]) }"},{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":["__function__:(context) =>\\n                      Erlang[\\"/=/2\\"](context.vars.x, Type.integer(2))"],"body":"__function__:(context) => { return Type.list([Type.atom(\\"b\\"), context.vars.x, context.vars.j]) }"}],"context":{"module":"__atom__:Elixir.MyModule","vars":{"i":"__integer__:10","j":"__integer__:20"}},"uniqueId":2},"y":2}]';

              const deserialized = deserialize(serialized);

              assert.deepStrictEqual(deserialized, {
                x: {
                  ...term,
                  clauses: deserialized.x.clauses,
                },
                y: 2,
              });

              assert.equal(deserialized.x.clauses.length, 2);

              assert.isFunction(deserialized.x.clauses[0].params);
              assert.isFunction(deserialized.x.clauses[0].guards[0]);
              assert.isFunction(deserialized.x.clauses[0].body);

              assert.isFunction(deserialized.x.clauses[1].params);
              assert.isFunction(deserialized.x.clauses[1].guards[0]);
              assert.isFunction(deserialized.x.clauses[1].body);

              const callResult = Interpreter.callAnonymousFunction(
                deserialized.x,
                [Type.integer(1)],
              );

              const expectedCallResult = Type.list([
                Type.atom("b"),
                Type.integer(1),
                Type.integer(20),
              ]);

              assert.deepStrictEqual(callResult, expectedCallResult);
            });

            // Not applicable
            // it("not versioned", () => {});
          });

          describe("atom", () => {
            const term = Type.atom("abc");

            it("top-level", () => {
              const serialized = '[1,"__atom__:abc"]';
              const deserialized = deserialize(serialized);

              assert.deepStrictEqual(deserialized, term);
            });

            it("nested", () => {
              const serialized = '[1,{"x":"__atom__:abc","y":2}]';
              const deserialized = deserialize(serialized);
              const expected = {x: term, y: 2};

              assert.deepStrictEqual(deserialized, expected);
            });

            // Not applicable
            // it("not versioned", () => {});
          });

          describe("bitstring", () => {
            describe("binary", () => {
              describe("empty", () => {
                const term = Type.bitstring2("");

                it("top-level", () => {
                  const serialized = '[1,"__binary__:"]';
                  const deserialized = deserialize(serialized);

                  assert.isTrue(
                    Interpreter.isStrictlyEqual(deserialized, term),
                  );
                });

                it("nested", () => {
                  const nestedTerm = {x: term, y: 2};
                  const serialized = '[1,{"x":"__binary__:","y":2}]';
                  const deserialized = deserialize(serialized);

                  assert.equal(typeof deserialized, "object");
                  assert.deepStrictEqual(Object.keys(deserialized), ["x", "y"]);

                  assert.isTrue(
                    Interpreter.isStrictlyEqual(deserialized.x, nestedTerm.x),
                  );
                });

                // Not applicable
                // it("not versioned", () => {});
              });

              describe("non-empty", () => {
                const term = Type.bitstring2('a"bc');

                it("top-level", () => {
                  const serialized = '[1,"__binary__:a\\"bc"]';
                  const deserialized = deserialize(serialized);

                  assert.isTrue(
                    Interpreter.isStrictlyEqual(deserialized, term),
                  );
                });

                it("nested", () => {
                  const nestedTerm = {x: term, y: 2};
                  const serialized = '[1,{"x":"__binary__:a\\"bc","y":2}]';
                  const deserialized = deserialize(serialized);

                  assert.equal(typeof deserialized, "object");
                  assert.deepStrictEqual(Object.keys(deserialized), ["x", "y"]);

                  assert.isTrue(
                    Interpreter.isStrictlyEqual(deserialized.x, nestedTerm.x),
                  );
                });

                // Not applicable
                // it("not versioned", () => {});
              });
            });

            describe("non-binary", () => {
              const term = Type.bitstring2([1, 0, 1, 0]);

              it("top-level", () => {
                const serialized = '[1,{"type":"bitstring","bits":[1,0,1,0]}]';
                const deserialized = deserialize(serialized);

                assert.isTrue(Interpreter.isStrictlyEqual(deserialized, term));
              });

              it("nested", () => {
                const nestedTerm = {x: term, y: 2};

                const serialized =
                  '[1,{"x":{"type":"bitstring","bits":[1,0,1,0]},"y":2}]';

                const deserialized = deserialize(serialized);

                assert.equal(typeof deserialized, "object");
                assert.deepStrictEqual(Object.keys(deserialized), ["x", "y"]);

                assert.isTrue(
                  Interpreter.isStrictlyEqual(deserialized.x, nestedTerm.x),
                );
              });

              // Not applicable
              // it("not versioned", () => {});
            });
          });

          describe("float", () => {
            const term = Type.float(1.23);

            it("top-level", () => {
              const serialized = '[1,"__float__:1.23"]';
              const deserialized = deserialize(serialized);

              assert.deepStrictEqual(deserialized, term);
            });

            it("nested", () => {
              const serialized = '[1,{"x":"__float__:1.23","y":2}]';
              const deserialized = deserialize(serialized);
              const expected = {x: term, y: 2};

              assert.deepStrictEqual(deserialized, expected);
            });

            // Not applicable
            // it("not versioned", () => {});
          });

          describe("integer", () => {
            const term = Type.integer(90071992547409919007199254740991n);

            it("top-level", () => {
              const serialized =
                '[1,"__integer__:90071992547409919007199254740991"]';

              const deserialized = deserialize(serialized);

              assert.deepStrictEqual(deserialized, term);
            });

            it("nested", () => {
              const serialized =
                '[1,{"x":"__integer__:90071992547409919007199254740991","y":2}]';

              const deserialized = deserialize(serialized);
              const expected = {x: term, y: 2};

              assert.deepStrictEqual(deserialized, expected);
            });

            // Not applicable
            // it("not versioned", () => {});
          });

          describe("map", () => {
            const term = Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.float(2.34)],
            ]);

            it("top-level", () => {
              const serialized =
                '[1,{"type":"map","data":[["__atom__:a", "__integer__:1"],["__atom__:b", "__float__:2.34"]]}]';

              const deserialized = deserialize(serialized);

              assert.deepStrictEqual(deserialized, term);
            });

            it("nested", () => {
              const serialized =
                '[1,{"x":{"type":"map","data":[["__atom__:a", "__integer__:1"],["__atom__:b", "__float__:2.34"]]},"y":2}]';

              const deserialized = deserialize(serialized);
              const expected = {x: term, y: 2};

              assert.deepStrictEqual(deserialized, expected);
            });

            // Not applicable
            // it("not versioned", () => {});
          });

          describe("tuple", () => {
            const term = Type.tuple([Type.integer(1), Type.float(1.23)]);

            it("top-level", () => {
              const serialized =
                '[1,{"type":"tuple","data":["__integer__:1","__float__:1.23"]}]';

              const deserialized = deserialize(serialized);

              assert.deepStrictEqual(deserialized, term);
            });

            it("nested", () => {
              const serialized =
                '[1,{"x":{"type":"tuple","data":["__integer__:1","__float__:1.23"]},"y":2}]';

              const deserialized = deserialize(serialized);
              const expected = {x: term, y: 2};

              assert.deepStrictEqual(deserialized, expected);
            });

            // Not applicable
            // it("not versioned", () => {});
          });
        });
      });
    });
  });
});
