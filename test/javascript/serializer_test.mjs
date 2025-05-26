"use strict";

import {
  assert,
  // contextFixture,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
// import Sequence from "../../assets/js/sequence.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Serializer", () => {
  describe("serialize()", () => {
    const serialize = Serializer.serialize;

    describe("boxed terms", () => {
      describe("atom", () => {
        it("top-level", () => {
          const term = Type.atom('x"yz');
          const expected = '[2,"ax\\"yz"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {k: Type.atom('x"yz'), m: 9};
          const expected = '[2,{"k":"ax\\"yz","m":9}]';

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

        describe("function", () => {
          it("top-level", () => {
            assert.throw(
              () => serialize(() => 123),
              HologramRuntimeError,
              'type "function" is not supported by the serializer',
            );
          });

          it("nested", () => {
            assert.throw(
              () => serialize({a: () => 123}),
              HologramRuntimeError,
              'type "function" is not supported by the serializer',
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
    //       describe("anonymous function", () => {
    //         beforeEach(() => {
    //           Sequence.reset();
    //         });

    //         describe("top-level", () => {
    //           describe("having capture info", () => {
    //             it("full scope", () => {
    //               const term = Type.functionCapture(
    //                 "Calendar.ISO",
    //                 "parse_date",
    //                 2,
    //                 [
    //                   (param) => Type.integer(param),
    //                   (param) => Type.bitstring2(param),
    //                 ],
    //                 contextFixture(),
    //               );

    //               const expected =
    //                 '[2,{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO","clauses":["__function__:(param) => Type.integer(param)","__function__:(param) => Type.bitstring2(param)"],"context":{"module":"a:Elixir.MyModule","vars":{}},"uniqueId":1}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.functionCapture(
    //                 "Calendar.ISO",
    //                 "parse_date",
    //                 2,
    //                 [],
    //                 contextFixture(),
    //               );

    //               const expected =
    //                 '[2,{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO"}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });

    //           describe("not having capture info", () => {
    //             it("full scope", () => {
    //               const term = Type.anonymousFunction(
    //                 1,
    //                 [
    //                   {
    //                     params: (_context) => [Type.variablePattern("x")],
    //                     guards: [],
    //                     // prettier-ignore
    //                     body: (_context) => { return Type.atom("expr_a"); },
    //                   },
    //                   {
    //                     params: (_context) => [Type.variablePattern("y")],
    //                     guards: [],
    //                     // prettier-ignore
    //                     body: (_context) => { return Type.atom("expr_b"); },
    //                   },
    //                 ],
    //                 contextFixture({vars: {a: 10, b: 20}}),
    //               );

    //               const expected =
    //                 '[2,{"type":"anonymous_function","arity":1,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"__function__:(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"a:Elixir.MyModule","vars":{"a":10,"b":20}},"uniqueId":1}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = Type.anonymousFunction(2, [], contextFixture());

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are anonymous functions that are not named function captures",
    //               );
    //             });
    //           });
    //         });

    //         describe("nested", () => {
    //           describe("having capture info", () => {
    //             it("full scope", () => {
    //               const term = {
    //                 a: Type.functionCapture(
    //                   "Calendar.ISO",
    //                   "parse_date",
    //                   2,
    //                   [
    //                     (param) => Type.integer(param),
    //                     (param) => Type.bitstring2(param),
    //                   ],
    //                   contextFixture(),
    //                 ),
    //                 b: 2,
    //               };

    //               const expected =
    //                 '[2,{"a":{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO","clauses":["__function__:(param) => Type.integer(param)","__function__:(param) => Type.bitstring2(param)"],"context":{"module":"a:Elixir.MyModule","vars":{}},"uniqueId":1},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {
    //                 a: Type.functionCapture(
    //                   "Calendar.ISO",
    //                   "parse_date",
    //                   2,
    //                   [],
    //                   contextFixture(),
    //                 ),
    //                 b: 2,
    //               };

    //               const expected =
    //                 '[2,{"a":{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO"},"b":2}]';

    //               assert.equal(serialize(term, false), expected);
    //             });
    //           });

    //           describe("not having capture info", () => {
    //             it("full scope", () => {
    //               const term = {
    //                 a: Type.anonymousFunction(
    //                   1,
    //                   [
    //                     {
    //                       params: (_context) => [Type.variablePattern("x")],
    //                       guards: [],
    //                       // prettier-ignore
    //                       body: (_context) => { return Type.atom("expr_a"); },
    //                     },
    //                     {
    //                       params: (_context) => [Type.variablePattern("y")],
    //                       guards: [],
    //                       // prettier-ignore
    //                       body: (_context) => { return Type.atom("expr_b"); },
    //                     },
    //                   ],
    //                   contextFixture({vars: {a: 10, b: 20}}),
    //                 ),
    //                 b: 2,
    //               };

    //               const expected =
    //                 '[2,{"a":{"type":"anonymous_function","arity":1,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"__function__:(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"a:Elixir.MyModule","vars":{"a":10,"b":20}},"uniqueId":1},"b":2}]';

    //               assert.equal(serialize(term, true), expected);
    //             });

    //             it("not full scope", () => {
    //               const term = {
    //                 a: Type.anonymousFunction(2, [], contextFixture()),
    //                 b: 2,
    //               };

    //               assert.throw(
    //                 () => serialize(term, false),
    //                 HologramRuntimeError,
    //                 "can't encode client terms that are anonymous functions that are not named function captures",
    //               );
    //             });
    //           });
    //         });

    //         it("not versioned", () => {
    //           const term = Type.functionCapture(
    //             "Calendar.ISO",
    //             "parse_date",
    //             2,
    //             [(param) => Type.integer(param), (param) => Type.bitstring2(param)],
    //             contextFixture(),
    //           );

    //           const expected =
    //             '{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO","clauses":["__function__:(param) => Type.integer(param)","__function__:(param) => Type.bitstring2(param)"],"context":{"module":"a:Elixir.MyModule","vars":{}},"uniqueId":1}';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });

    //       describe("bitstring", () => {
    //         describe("binary", () => {
    //           it("top-level", () => {
    //             const term = Type.bitstring2('a"bc');
    //             const expected = '[2,"b:61226263"]';

    //             assert.equal(serialize(term), expected);
    //           });

    //           it("nested", () => {
    //             const term = {a: Type.bitstring2('a"bc'), b: 2};
    //             const expected = '[2,{"a":"b:61226263","b":2}]';

    //             assert.equal(serialize(term), expected);
    //           });

    //           it("not versioned", () => {
    //             const term = Type.bitstring2('a"bc');
    //             const expected = '"b:61226263"';

    //             assert.equal(serialize(term, true, false), expected);
    //           });
    //         });

    //         describe("non-binary", () => {
    //           it("top-level", () => {
    //             const term = Type.bitstring2([1, 0, 1, 0]);
    //             const expected = '[2,"b:a0:4"]';

    //             assert.equal(serialize(term), expected);
    //           });

    //           it("nested", () => {
    //             const term = {a: Type.bitstring2([1, 0, 1, 0]), b: 2};

    //             const expected = '[2,{"a":"b:a0:4","b":2}]';

    //             assert.equal(serialize(term), expected);
    //           });

    //           it("not versioned", () => {
    //             const term = Type.bitstring2([1, 0, 1, 0]);
    //             const expected = '"b:a0:4"';

    //             assert.equal(serialize(term, true, false), expected);
    //           });
    //         });
    //       });

    //       describe("float", () => {
    //         it("top-level", () => {
    //           const term = Type.float(1.23);
    //           const expected = '[2,"f:1.23"]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("nested", () => {
    //           const term = {a: Type.float(1.23), b: 2};
    //           const expected = '[2,{"a":"f:1.23","b":2}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("not versioned", () => {
    //           const term = Type.float(1.23);
    //           const expected = '"f:1.23"';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });

    //       describe("integer", () => {
    //         it("top-level", () => {
    //           const term = Type.integer(123);
    //           const expected = '[2,"i:123"]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("nested", () => {
    //           const term = {a: Type.integer(123), b: 2};
    //           const expected = '[2,{"a":"i:123","b":2}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("not versioned", () => {
    //           const term = Type.integer(123);
    //           const expected = '"i:123"';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });

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

    //       describe("map", () => {
    //         it("top-level", () => {
    //           const term = Type.map([
    //             [Type.atom("x"), Type.integer(1)],
    //             [Type.bitstring2("y"), Type.float(1.23)],
    //           ]);

    //           const expected =
    //             '[2,{"t":"m","d":[["a:x","i:1"],["b:79","f:1.23"]]}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("nested", () => {
    //           const term = {
    //             a: Type.map([
    //               [Type.atom("x"), Type.integer(1)],
    //               [Type.bitstring2("y"), Type.float(1.23)],
    //             ]),
    //             b: 2,
    //           };

    //           const expected =
    //             '[2,{"a":{"t":"m","d":[["a:x","i:1"],["b:79","f:1.23"]]},"b":2}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("not versioned", () => {
    //           const term = Type.map([
    //             [Type.atom("x"), Type.integer(1)],
    //             [Type.bitstring2("y"), Type.float(1.23)],
    //           ]);

    //           const expected = '{"t":"m","d":[["a:x","i:1"],["b:79","f:1.23"]]}';

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

    //       describe("tuple", () => {
    //         it("top-level", () => {
    //           const term = Type.tuple([Type.integer(1), Type.float(1.23)]);

    //           const expected = '[2,{"t":"t","d":["i:1","f:1.23"]}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("nested", () => {
    //           const term = {
    //             a: Type.tuple([Type.integer(1), Type.float(1.23)]),
    //             b: 2,
    //           };

    //           const expected = '[2,{"a":{"t":"t","d":["i:1","f:1.23"]},"b":2}]';

    //           assert.equal(serialize(term), expected);
    //         });

    //         it("not versioned", () => {
    //           const term = Type.tuple([Type.integer(1), Type.float(1.23)]);

    //           const expected = '{"t":"t","d":["i:1","f:1.23"]}';

    //           assert.equal(serialize(term, true, false), expected);
    //         });
    //       });
    //     });
  });
});
