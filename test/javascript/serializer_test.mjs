"use strict";

import {
  assert,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Sequence from "../../assets/js/sequence.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Serializer", () => {
  describe("serialize()", () => {
    const DELIMITER = Serializer.DELIMITER;

    const serialize = Serializer.serialize;

    describe("boxed terms", () => {
      describe("atom", () => {
        it("top-level", () => {
          const term = Type.atom('x"yz');
          const expected = '[3,"ax\\"yz"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {k: Type.atom('x"yz')};
          const expected = '[3,{"k":"ax\\"yz"}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("bitstring", () => {
        it("top-level", () => {
          const term = Type.bitstring('a"bc');
          const expected = '[3,"b061226263"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.bitstring('a"bc')};
          const expected = '[3,{"a":"b061226263"}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("float", () => {
        describe("encoded as float", () => {
          it("top-level", () => {
            const term = Type.float(1.23);
            const expected = '[3,"f1.23"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.float(1.23)};
            const expected = '[3,{"a":"f1.23"}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("encoded as integer", () => {
          it("top-level", () => {
            const term = Type.float(123);
            const expected = '[3,"f123"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.float(123)};
            const expected = '[3,{"a":"f123"}]';

            assert.equal(serialize(term), expected);
          });
        });
      });

      describe("function", () => {
        beforeEach(() => {
          Sequence.reset();
        });

        const context = contextFixture({
          module: Type.alias("MyModule"),
          vars: {x: Type.integer(10), y: Type.integer(20)},
        });

        describe("capture", () => {
          describe("top-level", () => {
            it("server destination", () => {
              const term = Type.functionCapture(
                "Calendar.ISO",
                "date_to_string",
                4,
                [],
                context,
              );

              const expected = `[3,"cCalendar.ISO${DELIMITER}date_to_string${DELIMITER}4"]`;

              assert.equal(serialize(term, "server"), expected);
            });

            it("client destination", () => {
              const term = Type.functionCapture(
                "Calendar.ISO",
                "date_to_string",
                4,
                [
                  (param) => Type.integer(param),
                  (param) => Type.bitstring(param),
                ],
                context,
              );

              const expected =
                '[3,{"type":"sanonymous_function","arity":4,"capturedFunction":"sdate_to_string","capturedModule":"sCalendar.ISO","clauses":["u(param) => Type.integer(param)","u(param) => Type.bitstring(param)"],"context":{"module":"aElixir.MyModule","vars":{}},"uniqueId":1}]';

              assert.equal(serialize(term, "client"), expected);
            });
          });

          describe("nested", () => {
            it("server destination", () => {
              const term = {
                a: Type.functionCapture(
                  "Calendar.ISO",
                  "date_to_string",
                  4,
                  [],
                  context,
                ),
              };

              const expected = `[3,{"a":"cCalendar.ISO${DELIMITER}date_to_string${DELIMITER}4"}]`;

              assert.equal(serialize(term, "server"), expected);
            });

            it("client destination", () => {
              const term = {
                a: Type.functionCapture(
                  "Calendar.ISO",
                  "date_to_string",
                  4,
                  [
                    (param) => Type.integer(param),
                    (param) => Type.bitstring(param),
                  ],
                  context,
                ),
              };

              const expected =
                '[3,{"a":{"type":"sanonymous_function","arity":4,"capturedFunction":"sdate_to_string","capturedModule":"sCalendar.ISO","clauses":["u(param) => Type.integer(param)","u(param) => Type.bitstring(param)"],"context":{"module":"aElixir.MyModule","vars":{}},"uniqueId":1}}]';

              assert.equal(serialize(term, "client"), expected);
            });
          });
        });

        describe("non-capture", () => {
          describe("top-level", () => {
            it("server destination", () => {
              const term = Type.anonymousFunction(4, [], context);

              assert.throw(
                () => serialize(term, "server"),
                HologramRuntimeError,
                "cannot serialize function: not a named function capture",
              );
            });

            it("client destination", () => {
              const term = Type.anonymousFunction(
                4,
                [
                  {
                    params: (_context) => [Type.variablePattern("x")],
                    guards: [],
                    // prettier-ignore
                    body: (_context) => { return Type.atom("expr_a"); },
                  },
                  {
                    params: (_context) => [Type.variablePattern("y")],
                    guards: [],
                    // prettier-ignore
                    body: (_context) => { return Type.atom("expr_b"); },
                  },
                ],
                context,
              );

              const expected =
                '[3,{"type":"sanonymous_function","arity":4,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"u(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"u(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"aElixir.MyModule","vars":{"x":"i10","y":"i20"}},"uniqueId":1}]';

              assert.equal(serialize(term, "client"), expected);
            });
          });

          describe("nested", () => {
            it("server destination", () => {
              const term = {
                a: Type.anonymousFunction(4, [], context),
              };

              assert.throw(
                () => serialize(term, "server"),
                HologramRuntimeError,
                "cannot serialize function: not a named function capture",
              );
            });

            it("client destination", () => {
              const term = {
                a: Type.anonymousFunction(
                  4,
                  [
                    {
                      params: (_context) => [Type.variablePattern("x")],
                      guards: [],
                      // prettier-ignore
                      body: (_context) => { return Type.atom("expr_a"); },
                    },
                    {
                      params: (_context) => [Type.variablePattern("y")],
                      guards: [],
                      // prettier-ignore
                      body: (_context) => { return Type.atom("expr_b"); },
                    },
                  ],
                  context,
                ),
              };

              const expected =
                '[3,{"a":{"type":"sanonymous_function","arity":4,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"u(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"u(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"aElixir.MyModule","vars":{"x":"i10","y":"i20"}},"uniqueId":1}}]';

              assert.equal(serialize(term, "client"), expected);
            });
          });
        });
      });

      describe("integer", () => {
        it("top-level", () => {
          const term = Type.integer(123);
          const expected = '[3,"i123"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.integer(123)};
          const expected = '[3,{"a":"i123"}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("list", () => {
        it("top-level", () => {
          const term = Type.list([Type.atom("x"), Type.float(1.23)]);
          const expected = '[3,{"t":"l","d":["ax","f1.23"]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {b: Type.list([Type.atom("x"), Type.float(1.23)])};

          const expected = '[3,{"b":{"t":"l","d":["ax","f1.23"]}}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("map", () => {
        it("top-level", () => {
          const term = Type.map([
            [Type.atom("x"), Type.integer(1)],
            [Type.bitstring("y"), Type.float(1.23)],
          ]);

          const expected = '[3,{"t":"m","d":[["ax","i1"],["b079","f1.23"]]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.map([
              [Type.atom("x"), Type.integer(1)],
              [Type.bitstring("y"), Type.float(1.23)],
            ]),
          };

          const expected =
            '[3,{"a":{"t":"m","d":[["ax","i1"],["b079","f1.23"]]}}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("pid", () => {
        describe("originating in server", () => {
          describe("top-level", () => {
            const term = Type.pid('my_node@my_"host', [0, 11, 222], "server");
            const expected = `[3,"pmy_node@my_\\"host${DELIMITER}0,11,222${DELIMITER}server"]`;

            it("server destination", () => {
              assert.equal(serialize(term, "server"), expected);
            });

            it("client destination", () => {
              assert.equal(serialize(term, "client"), expected);
            });
          });

          describe("nested", () => {
            const term = {
              a: Type.pid('my_node@my_"host', [0, 11, 222], "server"),
            };

            const expected = `[3,{"a":"pmy_node@my_\\"host${DELIMITER}0,11,222${DELIMITER}server"}]`;

            it("server destination", () => {
              assert.equal(serialize(term, "server"), expected);
            });

            it("client destination", () => {
              assert.equal(serialize(term, "client"), expected);
            });
          });
        });

        describe("originating in client", () => {
          describe("top-level", () => {
            const term = Type.pid('my_node@my_"host', [0, 11, 222], "client");

            it("server destination", () => {
              assert.throw(
                () => serialize(term, "server"),
                HologramRuntimeError,
                "cannot serialize PID: origin is client but destination is server",
              );
            });

            it("client destination", () => {
              const expected = `[3,"pmy_node@my_\\"host${DELIMITER}0,11,222${DELIMITER}client"]`;

              assert.equal(serialize(term, "client"), expected);
            });
          });

          describe("nested", () => {
            const term = {
              a: Type.pid('my_node@my_"host', [0, 11, 222], "client"),
            };

            it("server destination", () => {
              assert.throw(
                () => serialize(term, "server"),
                HologramRuntimeError,
                "cannot serialize PID: origin is client but destination is server",
              );
            });

            it("client destination", () => {
              const expected = `[3,{"a":"pmy_node@my_\\"host${DELIMITER}0,11,222${DELIMITER}client"}]`;

              assert.equal(serialize(term, "client"), expected);
            });
          });
        });
      });

      describe("port", () => {
        describe("originating in server", () => {
          describe("top-level", () => {
            const term = Type.port('my_node@my_"host', [0, 11], "server");
            const expected = `[3,"omy_node@my_\\"host${DELIMITER}0,11${DELIMITER}server"]`;

            it("server destination", () => {
              assert.equal(serialize(term, "server"), expected);
            });

            it("client destination", () => {
              assert.equal(serialize(term, "client"), expected);
            });
          });

          describe("nested", () => {
            const term = {
              a: Type.port('my_node@my_"host', [0, 11], "server"),
            };

            const expected = `[3,{"a":"omy_node@my_\\"host${DELIMITER}0,11${DELIMITER}server"}]`;

            it("server destination", () => {
              assert.equal(serialize(term, "server"), expected);
            });

            it("client destination", () => {
              assert.equal(serialize(term, "client"), expected);
            });
          });
        });

        describe("originating in client", () => {
          describe("top-level", () => {
            const term = Type.port('my_node@my_"host', [0, 11], "client");

            it("server destination", () => {
              assert.throw(
                () => serialize(term, "server"),
                HologramRuntimeError,
                "cannot serialize port: origin is client but destination is server",
              );
            });

            it("client destination", () => {
              const expected = `[3,"omy_node@my_\\"host${DELIMITER}0,11${DELIMITER}client"]`;

              assert.equal(serialize(term, "client"), expected);
            });
          });

          describe("nested", () => {
            const term = {
              a: Type.port('my_node@my_"host', [0, 11], "client"),
            };

            it("server destination", () => {
              assert.throw(
                () => serialize(term, "server"),
                HologramRuntimeError,
                "cannot serialize port: origin is client but destination is server",
              );
            });

            it("client destination", () => {
              const expected = `[3,{"a":"omy_node@my_\\"host${DELIMITER}0,11${DELIMITER}client"}]`;

              assert.equal(serialize(term, "client"), expected);
            });
          });
        });
      });

      describe("reference", () => {
        describe("top-level", () => {
          const term = Type.reference('my_node@my_"host', 4, [1, 2, 3]);

          const expected =
            '[3,{"t":"r","n":"smy_node@my_\\"host","c":4,"i":[1,2,3]}]';

          it("server destination", () => {
            assert.equal(serialize(term, "server"), expected);
          });

          it("client destination", () => {
            assert.equal(serialize(term, "client"), expected);
          });
        });

        describe("nested", () => {
          const term = {
            a: Type.reference('my_node@my_"host', 4, [1, 2, 3]),
          };

          const expected =
            '[3,{"a":{"t":"r","n":"smy_node@my_\\"host","c":4,"i":[1,2,3]}}]';

          it("server destination", () => {
            assert.equal(serialize(term, "server"), expected);
          });

          it("client destination", () => {
            assert.equal(serialize(term, "client"), expected);
          });
        });
      });

      describe("tuple", () => {
        it("top-level", () => {
          const term = Type.tuple([Type.atom("x"), Type.float(1.23)]);
          const expected = '[3,{"t":"t","d":["ax","f1.23"]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {b: Type.tuple([Type.atom("x"), Type.float(1.23)])};

          const expected = '[3,{"b":{"t":"t","d":["ax","f1.23"]}}]';

          assert.equal(serialize(term), expected);
        });
      });
    });

    describe("JS terms", () => {
      describe("supported", () => {
        describe("array", () => {
          it("top-level", () => {
            const term = [9, 8.76];
            const expected = "[3,[9,8.76]]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 9, b: [8, 7.65]};
            const expected = '[3,{"a":9,"b":[8,7.65]}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("float", () => {
          it("top-level", () => {
            const term = 9.87;
            const expected = "[3,9.87]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 9.87};
            const expected = '[3,{"a":9.87}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("function", () => {
          describe("longhand syntax", () => {
            // prettier-ignore
            const fun = function (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring('a"bc'); return Type.list([integer, binary, param2]); };

            it("top-level", () => {
              const expected = `[3,"ufunction (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"]`;

              assert.equal(serialize(fun), expected);
            });

            it("nested", () => {
              const term = {a: fun};
              const expected = `[3,{"a":"ufunction (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"}]`;

              assert.equal(serialize(term), expected);
            });
          });

          describe("shorthand syntax", () => {
            // prettier-ignore
            const fun = (param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring('a"bc'); return Type.list([integer, binary, param2]); };

            it("top-level", () => {
              const expected = `[3,"u(param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"]`;

              assert.equal(serialize(fun), expected);
            });

            it("nested", () => {
              const term = {a: fun};
              const expected = `[3,{"a":"u(param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"}]`;

              assert.equal(serialize(term), expected);
            });
          });
        });

        describe("integer", () => {
          it("top-level", () => {
            const term = 987;
            const expected = "[3,987]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 987};
            const expected = '[3,{"a":987}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("null", () => {
          it("top-level", () => {
            const term = null;
            const expected = "[3,null]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: null};
            const expected = '[3,{"a":null}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("object", () => {
          it("top-level", () => {
            const term = {a: 9, 'b"cd': 8.76};
            const expected = '[3,{"a":9,"b\\"cd":8.76}]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 9, b: {c: 8.76, 'd"ef': 7}};
            const expected = '[3,{"a":9,"b":{"c":8.76,"d\\"ef":7}}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("string", () => {
          it("top-level", () => {
            const term = 'x"yz';
            const expected = '[3,"sx\\"yz"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 'x"yz', b: 2};
            const expected = '[3,{"a":"sx\\"yz","b":2}]';

            assert.equal(serialize(term), expected);
          });
        });
      });

      describe("not supported", () => {
        describe("BigInt", () => {
          it("top-level", () => {
            assert.throw(
              () => serialize(123n),
              HologramRuntimeError,
              'type "bigint" is not supported by the serializer',
            );
          });

          it("nested", () => {
            assert.throw(
              () => serialize({a: 123n}),
              HologramRuntimeError,
              'type "bigint" is not supported by the serializer',
            );
          });
        });

        describe("boolean", () => {
          it("top-level", () => {
            assert.throw(
              () => serialize(true),
              HologramRuntimeError,
              'type "boolean" is not supported by the serializer',
            );
          });

          it("nested", () => {
            assert.throw(
              () => serialize({a: true}),
              HologramRuntimeError,
              'type "boolean" is not supported by the serializer',
            );
          });
        });

        describe("undefined", () => {
          it("top-level", () => {
            assert.throw(
              () => serialize(undefined),
              HologramRuntimeError,
              'type "undefined" is not supported by the serializer',
            );
          });

          it("nested", () => {
            assert.throw(
              () => serialize({a: undefined}),
              HologramRuntimeError,
              'type "undefined" is not supported by the serializer',
            );
          });
        });
      });
    });
  });
});
