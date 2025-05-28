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
    const serialize = Serializer.serialize;

    describe("boxed terms", () => {
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

              const expected = '[2,"cCalendar.ISO:date_to_string:4"]';

              assert.equal(serialize(term, "server"), expected);
            });

            it("client destination", () => {
              const term = Type.functionCapture(
                "Calendar.ISO",
                "date_to_string",
                4,
                [
                  (param) => Type.integer(param),
                  (param) => Type.bitstring2(param),
                ],
                context,
              );

              const expected =
                '[2,{"type":"sanonymous_function","arity":4,"capturedFunction":"sdate_to_string","capturedModule":"sCalendar.ISO","clauses":["u(param) => Type.integer(param)","u(param) => Type.bitstring2(param)"],"context":{"module":"aElixir.MyModule","vars":{}},"uniqueId":1}]';

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

              const expected = '[2,{"a":"cCalendar.ISO:date_to_string:4"}]';

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
                    (param) => Type.bitstring2(param),
                  ],
                  context,
                ),
              };

              const expected =
                '[2,{"a":{"type":"sanonymous_function","arity":4,"capturedFunction":"sdate_to_string","capturedModule":"sCalendar.ISO","clauses":["u(param) => Type.integer(param)","u(param) => Type.bitstring2(param)"],"context":{"module":"aElixir.MyModule","vars":{}},"uniqueId":1}}]';

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
                "can't encode client terms that are anonymous functions that are not named function captures",
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
                '[2,{"type":"sanonymous_function","arity":4,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"u(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"u(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"aElixir.MyModule","vars":{"x":"i10","y":"i20"}},"uniqueId":1}]';

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
                "can't encode client terms that are anonymous functions that are not named function captures",
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
                '[2,{"a":{"type":"sanonymous_function","arity":4,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"u(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"u(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"u(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"aElixir.MyModule","vars":{"x":"i10","y":"i20"}},"uniqueId":1}}]';

              assert.equal(serialize(term, "client"), expected);
            });
          });
        });
      });

      describe("atom", () => {
        it("top-level", () => {
          const term = Type.atom('x"yz');
          const expected = '[2,"ax\\"yz"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {k: Type.atom('x"yz')};
          const expected = '[2,{"k":"ax\\"yz"}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("bitstring", () => {
        it("top-level", () => {
          const term = Type.bitstring2('a"bc');
          const expected = '[2,"b061226263"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.bitstring2('a"bc')};
          const expected = '[2,{"a":"b061226263"}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("float", () => {
        describe("encoded as float", () => {
          it("top-level", () => {
            const term = Type.float(1.23);
            const expected = '[2,"f1.23"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.float(1.23)};
            const expected = '[2,{"a":"f1.23"}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("encoded as integer", () => {
          it("top-level", () => {
            const term = Type.float(123);
            const expected = '[2,"f123"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.float(123)};
            const expected = '[2,{"a":"f123"}]';

            assert.equal(serialize(term), expected);
          });
        });
      });

      describe("integer", () => {
        it("top-level", () => {
          const term = Type.integer(123);
          const expected = '[2,"i123"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.integer(123)};
          const expected = '[2,{"a":"i123"}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("map", () => {
        it("top-level", () => {
          const term = Type.map([
            [Type.atom("x"), Type.integer(1)],
            [Type.bitstring2("y"), Type.float(1.23)],
          ]);

          const expected = '[2,{"t":"m","d":[["ax","i1"],["b079","f1.23"]]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.map([
              [Type.atom("x"), Type.integer(1)],
              [Type.bitstring2("y"), Type.float(1.23)],
            ]),
          };

          const expected =
            '[2,{"a":{"t":"m","d":[["ax","i1"],["b079","f1.23"]]}}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("tuple", () => {
        it("top-level", () => {
          const term = Type.tuple([Type.atom("x"), Type.float(1.23)]);
          const expected = '[2,{"t":"t","d":["ax","f1.23"]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {b: Type.tuple([Type.atom("x"), Type.float(1.23)])};

          const expected = '[2,{"b":{"t":"t","d":["ax","f1.23"]}}]';

          assert.equal(serialize(term), expected);
        });
      });
    });

    describe("JS terms", () => {
      describe("supported", () => {
        describe("array", () => {
          it("top-level", () => {
            const term = [9, 8.76];
            const expected = "[2,[9,8.76]]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 9, b: [8, 7.65]};
            const expected = '[2,{"a":9,"b":[8,7.65]}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("float", () => {
          it("top-level", () => {
            const term = 9.87;
            const expected = "[2,9.87]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 9.87};
            const expected = '[2,{"a":9.87}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("function", () => {
          describe("longhand syntax", () => {
            // prettier-ignore
            const fun = function (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring2('a"bc'); return Type.list([integer, binary, param2]); };

            it("top-level", () => {
              const expected = `[2,"ufunction (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring2('a\\"bc'); return Type.list([integer, binary, param2]); }"]`;

              assert.equal(serialize(fun), expected);
            });

            it("nested", () => {
              const term = {a: fun};
              const expected = `[2,{"a":"ufunction (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring2('a\\"bc'); return Type.list([integer, binary, param2]); }"}]`;

              assert.equal(serialize(term), expected);
            });
          });

          describe("shorthand syntax", () => {
            // prettier-ignore
            const fun = (param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring2('a"bc'); return Type.list([integer, binary, param2]); };

            it("top-level", () => {
              const expected = `[2,"u(param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring2('a\\"bc'); return Type.list([integer, binary, param2]); }"]`;

              assert.equal(serialize(fun), expected);
            });

            it("nested", () => {
              const term = {a: fun};
              const expected = `[2,{"a":"u(param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring2('a\\"bc'); return Type.list([integer, binary, param2]); }"}]`;

              assert.equal(serialize(term), expected);
            });
          });
        });

        describe("integer", () => {
          it("top-level", () => {
            const term = 987;
            const expected = "[2,987]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 987};
            const expected = '[2,{"a":987}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("null", () => {
          it("top-level", () => {
            const term = null;
            const expected = "[2,null]";

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: null};
            const expected = '[2,{"a":null}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("object", () => {
          it("top-level", () => {
            const term = {a: 9, 'b"cd': 8.76};
            const expected = '[2,{"a":9,"b\\"cd":8.76}]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 9, b: {c: 8.76, 'd"ef': 7}};
            const expected = '[2,{"a":9,"b":{"c":8.76,"d\\"ef":7}}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("string", () => {
          it("top-level", () => {
            const term = 'x"yz';
            const expected = '[2,"sx\\"yz"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: 'x"yz', b: 2};
            const expected = '[2,{"a":"sx\\"yz","b":2}]';

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

    //     describe("boxed terms", () => {
    //       describe("list", () => {
    //         it("top-level", () => {
    //           const term = Type.list([Type.integer(1), Type.float(1.23)]);

    //           const expected =
    //             '[2,{"type":"list","data":["i:1","f:1.23"],"isProper":true}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("nested", () => {
    //           const term = {
    //             a: Type.list([Type.integer(1), Type.float(1.23)]),
    //             b: 2,
    //           };

    //           const expected =
    //             '[2,{"a":{"type":"list","data":["i:1","f:1.23"],"isProper":true},"b":2}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("not versioned", () => {
    //           const term = Type.list([Type.integer(1), Type.float(1.23)]);

    //           const expected =
    //             '{"type":"list","data":["i:1","f:1.23"],"isProper":true}';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });

    //       describe("pid", () => {
    //         describe("top-level", () => {
    //           describe("originating in client", () => {
    //             it("full scope", () => {
    //               const term = Type.pid('my_node@my_"host', [0, 11, 222], "client");

    //               const expected =
    //                 '[2,{"type":"pid","node":"my_node@my_\\"host","origin":"client","segments":[0,11,222]}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.pid("my_node@my_host", [0, 11, 222], "client");

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are PIDs originating in client",
    //               );
    //             });
    //           });

    //           describe("originating in server", () => {
    //             it("full scope", () => {
    //               const term = Type.pid('my_node@my_"host', [0, 11, 222], "server");

    //               const expected =
    //                 '[2,{"type":"pid","node":"my_node@my_\\"host","origin":"server","segments":[0,11,222]}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.pid("my_node@my_host", [0, 11, 222], "server");
    //               const expected = '[2,{"type":"pid","segments":[0,11,222]}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });
    //         });

    //         describe("nested", () => {
    //           describe("originating in client", () => {
    //             it("full scope", () => {
    //               const term = {
    //                 a: Type.pid('my_node@my_"host', [0, 11, 222], "client"),
    //                 b: 2,
    //               };

    //               const expected =
    //                 '[2,{"a":{"type":"pid","node":"my_node@my_\\"host","origin":"client","segments":[0,11,222]},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {
    //                 a: Type.pid("my_node@my_host", [0, 11, 222], "client"),
    //                 b: 2,
    //               };

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are PIDs originating in client",
    //               );
    //             });
    //           });

    //           describe("originating in server", () => {
    //             it("full scope", () => {
    //               const term = {
    //                 a: Type.pid('my_node@my_"host', [0, 11, 222], "server"),
    //                 b: 2,
    //               };

    //               const expected =
    //                 '[2,{"a":{"type":"pid","node":"my_node@my_\\"host","origin":"server","segments":[0,11,222]},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {
    //                 a: Type.pid("my_node@my_host", [0, 11, 222], "server"),
    //                 b: 2,
    //               };

    //               const expected =
    //                 '[2,{"a":{"type":"pid","segments":[0,11,222]},"b":2}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });
    //         });

    //         it("not versioned", () => {
    //           const term = Type.pid('my_node@my_"host', [0, 11, 222], "client");

    //           const expected =
    //             '{"type":"pid","node":"my_node@my_\\"host","origin":"client","segments":[0,11,222]}';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });

    //       describe("port", () => {
    //         describe("top-level", () => {
    //           describe("originating in client", () => {
    //             it("full scope", () => {
    //               const term = Type.port("0.11", "client");

    //               const expected =
    //                 '[2,{"type":"port","origin":"client","value":"0.11"}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.port("0.11", "client");

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are ports originating in client",
    //               );
    //             });
    //           });

    //           describe("originating in server", () => {
    //             it("full scope", () => {
    //               const term = Type.port("0.11", "server");

    //               const expected =
    //                 '[2,{"type":"port","origin":"server","value":"0.11"}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.port("0.11", "server");
    //               const expected = '[2,{"type":"port","value":"0.11"}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });
    //         });

    //         describe("nested", () => {
    //           describe("originating in client", () => {
    //             it("full scope", () => {
    //               const term = {a: Type.port("0.11", "client"), b: 2};

    //               const expected =
    //                 '[2,{"a":{"type":"port","origin":"client","value":"0.11"},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {a: Type.port("0.11", "client"), b: 2};

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are ports originating in client",
    //               );
    //             });
    //           });

    //           describe("originating in server", () => {
    //             it("full scope", () => {
    //               const term = {a: Type.port("0.11", "server"), b: 2};

    //               const expected =
    //                 '[2,{"a":{"type":"port","origin":"server","value":"0.11"},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {a: Type.port("0.11", "server"), b: 2};

    //               const expected = '[2,{"a":{"type":"port","value":"0.11"},"b":2}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });
    //         });

    //         it("not versioned", () => {
    //           const term = Type.port("0.11", "client");

    //           const expected = '{"type":"port","origin":"client","value":"0.11"}';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });

    //       describe("reference", () => {
    //         describe("top-level", () => {
    //           describe("originating in client", () => {
    //             it("full scope", () => {
    //               const term = Type.reference("0.1.2.3", "client");

    //               const expected =
    //                 '[2,{"type":"reference","origin":"client","value":"0.1.2.3"}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.reference("0.1.2.3", "client");

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are references originating in client",
    //               );
    //             });
    //           });

    //           describe("originating in server", () => {
    //             it("full scope", () => {
    //               const term = Type.reference("0.1.2.3", "server");

    //               const expected =
    //                 '[2,{"type":"reference","origin":"server","value":"0.1.2.3"}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.reference("0.1.2.3", "server");
    //               const expected = '[2,{"type":"reference","value":"0.1.2.3"}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });
    //         });

    //         describe("nested", () => {
    //           describe("originating in client", () => {
    //             it("full scope", () => {
    //               const term = {a: Type.reference("0.1.2.3", "client"), b: 2};

    //               const expected =
    //                 '[2,{"a":{"type":"reference","origin":"client","value":"0.1.2.3"},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {a: Type.reference("0.1.2.3", "client"), b: 2};

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are references originating in client",
    //               );
    //             });
    //           });

    //           describe("originating in server", () => {
    //             it("full scope", () => {
    //               const term = {a: Type.reference("0.1.2.3", "server"), b: 2};

    //               const expected =
    //                 '[2,{"a":{"type":"reference","origin":"server","value":"0.1.2.3"},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {a: Type.reference("0.1.2.3", "server"), b: 2};

    //               const expected =
    //                 '[2,{"a":{"type":"reference","value":"0.1.2.3"},"b":2}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });
    //         });

    //         it("not versioned", () => {
    //           const term = Type.reference("0.1.2.3", "client");

    //           const expected =
    //             '{"type":"reference","origin":"client","value":"0.1.2.3"}';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });
    //     });
  });
});
