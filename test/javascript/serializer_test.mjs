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
      describe("anonymous function", () => {
        beforeEach(() => {
          Sequence.reset();
        });

        describe("top-level", () => {
          describe("having capture info", () => {
            it("full scope", () => {
              const term = Type.functionCapture(
                "Calendar.ISO",
                "parse_date",
                2,
                [
                  (param) => Type.integer(param),
                  (param) => Type.bitstring(param),
                ],
                contextFixture(),
              );

              const expected =
                '[1,{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO","clauses":["__function__:(param) => Type.integer(param)","__function__:(param) => Type.bitstring(param)"],"context":{"module":"__atom__:Elixir.MyModule","vars":{}},"uniqueId":1}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.functionCapture(
                "Calendar.ISO",
                "parse_date",
                2,
                [],
                contextFixture(),
              );

              const expected =
                '[1,{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO"}]';

              assert.equal(serialize(term, false), expected);
            });
          });

          describe("not having capture info", () => {
            it("full scope", () => {
              const term = Type.anonymousFunction(
                1,
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
                contextFixture({vars: {a: 10, b: 20}}),
              );

              const expected =
                '[1,{"type":"anonymous_function","arity":1,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"__function__:(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"__atom__:Elixir.MyModule","vars":{"a":10,"b":20}},"uniqueId":1}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.anonymousFunction(2, [], contextFixture());

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are anonymous functions that are not named function captures",
              );
            });
          });
        });

        describe("nested", () => {
          describe("having capture info", () => {
            it("full scope", () => {
              const term = {
                a: Type.functionCapture(
                  "Calendar.ISO",
                  "parse_date",
                  2,
                  [
                    (param) => Type.integer(param),
                    (param) => Type.bitstring(param),
                  ],
                  contextFixture(),
                ),
                b: 2,
              };

              const expected =
                '[1,{"a":{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO","clauses":["__function__:(param) => Type.integer(param)","__function__:(param) => Type.bitstring(param)"],"context":{"module":"__atom__:Elixir.MyModule","vars":{}},"uniqueId":1},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {
                a: Type.functionCapture(
                  "Calendar.ISO",
                  "parse_date",
                  2,
                  [],
                  contextFixture(),
                ),
                b: 2,
              };

              const expected =
                '[1,{"a":{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO"},"b":2}]';

              assert.equal(serialize(term, false), expected);
            });
          });

          describe("not having capture info", () => {
            it("full scope", () => {
              const term = {
                a: Type.anonymousFunction(
                  1,
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
                  contextFixture({vars: {a: 10, b: 20}}),
                ),
                b: 2,
              };

              const expected =
                '[1,{"a":{"type":"anonymous_function","arity":1,"capturedFunction":null,"capturedModule":null,"clauses":[{"params":"__function__:(_context) => [Type.variablePattern(\\"x\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_a\\"); }"},{"params":"__function__:(_context) => [Type.variablePattern(\\"y\\")]","guards":[],"body":"__function__:(_context) => { return Type.atom(\\"expr_b\\"); }"}],"context":{"module":"__atom__:Elixir.MyModule","vars":{"a":10,"b":20}},"uniqueId":1},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {
                a: Type.anonymousFunction(2, [], contextFixture()),
                b: 2,
              };

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are anonymous functions that are not named function captures",
              );
            });
          });
        });

        it("not versioned", () => {
          const term = Type.functionCapture(
            "Calendar.ISO",
            "parse_date",
            2,
            [(param) => Type.integer(param), (param) => Type.bitstring(param)],
            contextFixture(),
          );

          const expected =
            '{"type":"anonymous_function","arity":2,"capturedFunction":"parse_date","capturedModule":"Calendar.ISO","clauses":["__function__:(param) => Type.integer(param)","__function__:(param) => Type.bitstring(param)"],"context":{"module":"__atom__:Elixir.MyModule","vars":{}},"uniqueId":1}';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("atom", () => {
        it("top-level", () => {
          const term = Type.atom('a"bc');
          const expected = '[1,"__atom__:a\\"bc"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.atom('a"bc'), b: 2};
          const expected = '[1,{"a":"__atom__:a\\"bc","b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = Type.atom('a"bc');
          const expected = '"__atom__:a\\"bc"';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("bitstring", () => {
        describe("binary", () => {
          it("top-level", () => {
            const term = Type.bitstring('a"bc');
            const expected = '[1,"__binary__:a\\"bc"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.bitstring('a"bc'), b: 2};
            const expected = '[1,{"a":"__binary__:a\\"bc","b":2}]';

            assert.equal(serialize(term), expected);
          });

          it("not versioned", () => {
            const term = Type.bitstring('a"bc');
            const expected = '"__binary__:a\\"bc"';

            assert.equal(serialize(term, true, false), expected);
          });
        });

        describe("non-binary", () => {
          it("top-level", () => {
            const term = Type.bitstring([1, 0, 1, 0]);
            const expected = '[1,{"type":"bitstring","bits":[1,0,1,0]}]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.bitstring([1, 0, 1, 0]), b: 2};

            const expected =
              '[1,{"a":{"type":"bitstring","bits":[1,0,1,0]},"b":2}]';

            assert.equal(serialize(term), expected);
          });

          it("not versioned", () => {
            const term = Type.bitstring([1, 0, 1, 0]);
            const expected = '{"type":"bitstring","bits":[1,0,1,0]}';

            assert.equal(serialize(term, true, false), expected);
          });
        });
      });

      describe("float", () => {
        it("top-level", () => {
          const term = Type.float(1.23);
          const expected = '[1,"__float__:1.23"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.float(1.23), b: 2};
          const expected = '[1,{"a":"__float__:1.23","b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = Type.float(1.23);
          const expected = '"__float__:1.23"';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("integer", () => {
        it("top-level", () => {
          const term = Type.integer(123);
          const expected = '[1,"__integer__:123"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.integer(123), b: 2};
          const expected = '[1,{"a":"__integer__:123","b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = Type.integer(123);
          const expected = '"__integer__:123"';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("list", () => {
        it("top-level", () => {
          const term = Type.list([Type.integer(1), Type.float(1.23)]);

          const expected =
            '[1,{"type":"list","data":["__integer__:1","__float__:1.23"],"isProper":true}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.list([Type.integer(1), Type.float(1.23)]),
            b: 2,
          };

          const expected =
            '[1,{"a":{"type":"list","data":["__integer__:1","__float__:1.23"],"isProper":true},"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = Type.list([Type.integer(1), Type.float(1.23)]);

          const expected =
            '{"type":"list","data":["__integer__:1","__float__:1.23"],"isProper":true}';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("map", () => {
        it("top-level", () => {
          const term = Type.map([
            [Type.atom("x"), Type.integer(1)],
            [Type.bitstring("y"), Type.float(1.23)],
          ]);

          const expected =
            '[1,{"type":"map","data":[["__atom__:x","__integer__:1"],["__binary__:y","__float__:1.23"]]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.map([
              [Type.atom("x"), Type.integer(1)],
              [Type.bitstring("y"), Type.float(1.23)],
            ]),
            b: 2,
          };

          const expected =
            '[1,{"a":{"type":"map","data":[["__atom__:x","__integer__:1"],["__binary__:y","__float__:1.23"]]},"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = Type.map([
            [Type.atom("x"), Type.integer(1)],
            [Type.bitstring("y"), Type.float(1.23)],
          ]);

          const expected =
            '{"type":"map","data":[["__atom__:x","__integer__:1"],["__binary__:y","__float__:1.23"]]}';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("pid", () => {
        describe("top-level", () => {
          describe("originating in client", () => {
            it("full scope", () => {
              const term = Type.pid('my_node@my_"host', [0, 11, 222], "client");

              const expected =
                '[1,{"type":"pid","node":"my_node@my_\\"host","origin":"client","segments":[0,11,222]}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.pid("my_node@my_host", [0, 11, 222], "client");

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are PIDs originating in client",
              );
            });
          });

          describe("originating in server", () => {
            it("full scope", () => {
              const term = Type.pid('my_node@my_"host', [0, 11, 222], "server");

              const expected =
                '[1,{"type":"pid","node":"my_node@my_\\"host","origin":"server","segments":[0,11,222]}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.pid("my_node@my_host", [0, 11, 222], "server");
              const expected = '[1,{"type":"pid","segments":[0,11,222]}]';

              assert.equal(serialize(term, false), expected);
            });
          });
        });

        describe("nested", () => {
          describe("originating in client", () => {
            it("full scope", () => {
              const term = {
                a: Type.pid('my_node@my_"host', [0, 11, 222], "client"),
                b: 2,
              };

              const expected =
                '[1,{"a":{"type":"pid","node":"my_node@my_\\"host","origin":"client","segments":[0,11,222]},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {
                a: Type.pid("my_node@my_host", [0, 11, 222], "client"),
                b: 2,
              };

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are PIDs originating in client",
              );
            });
          });

          describe("originating in server", () => {
            it("full scope", () => {
              const term = {
                a: Type.pid('my_node@my_"host', [0, 11, 222], "server"),
                b: 2,
              };

              const expected =
                '[1,{"a":{"type":"pid","node":"my_node@my_\\"host","origin":"server","segments":[0,11,222]},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {
                a: Type.pid("my_node@my_host", [0, 11, 222], "server"),
                b: 2,
              };

              const expected =
                '[1,{"a":{"type":"pid","segments":[0,11,222]},"b":2}]';

              assert.equal(serialize(term, false), expected);
            });
          });
        });

        it("not versioned", () => {
          const term = Type.pid('my_node@my_"host', [0, 11, 222], "client");

          const expected =
            '{"type":"pid","node":"my_node@my_\\"host","origin":"client","segments":[0,11,222]}';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("port", () => {
        describe("top-level", () => {
          describe("originating in client", () => {
            it("full scope", () => {
              const term = Type.port("0.11", "client");

              const expected =
                '[1,{"type":"port","origin":"client","value":"0.11"}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.port("0.11", "client");

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are ports originating in client",
              );
            });
          });

          describe("originating in server", () => {
            it("full scope", () => {
              const term = Type.port("0.11", "server");

              const expected =
                '[1,{"type":"port","origin":"server","value":"0.11"}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.port("0.11", "server");
              const expected = '[1,{"type":"port","value":"0.11"}]';

              assert.equal(serialize(term, false), expected);
            });
          });
        });

        describe("nested", () => {
          describe("originating in client", () => {
            it("full scope", () => {
              const term = {a: Type.port("0.11", "client"), b: 2};

              const expected =
                '[1,{"a":{"type":"port","origin":"client","value":"0.11"},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {a: Type.port("0.11", "client"), b: 2};

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are ports originating in client",
              );
            });
          });

          describe("originating in server", () => {
            it("full scope", () => {
              const term = {a: Type.port("0.11", "server"), b: 2};

              const expected =
                '[1,{"a":{"type":"port","origin":"server","value":"0.11"},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {a: Type.port("0.11", "server"), b: 2};

              const expected = '[1,{"a":{"type":"port","value":"0.11"},"b":2}]';

              assert.equal(serialize(term, false), expected);
            });
          });
        });

        it("not versioned", () => {
          const term = Type.port("0.11", "client");

          const expected = '{"type":"port","origin":"client","value":"0.11"}';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("reference", () => {
        describe("top-level", () => {
          describe("originating in client", () => {
            it("full scope", () => {
              const term = Type.reference("0.1.2.3", "client");

              const expected =
                '[1,{"type":"reference","origin":"client","value":"0.1.2.3"}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.reference("0.1.2.3", "client");

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are references originating in client",
              );
            });
          });

          describe("originating in server", () => {
            it("full scope", () => {
              const term = Type.reference("0.1.2.3", "server");

              const expected =
                '[1,{"type":"reference","origin":"server","value":"0.1.2.3"}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = Type.reference("0.1.2.3", "server");
              const expected = '[1,{"type":"reference","value":"0.1.2.3"}]';

              assert.equal(serialize(term, false), expected);
            });
          });
        });

        describe("nested", () => {
          describe("originating in client", () => {
            it("full scope", () => {
              const term = {a: Type.reference("0.1.2.3", "client"), b: 2};

              const expected =
                '[1,{"a":{"type":"reference","origin":"client","value":"0.1.2.3"},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {a: Type.reference("0.1.2.3", "client"), b: 2};

              assert.throw(
                () => serialize(term, false),
                HologramRuntimeError,
                "can't encode client terms that are references originating in client",
              );
            });
          });

          describe("originating in server", () => {
            it("full scope", () => {
              const term = {a: Type.reference("0.1.2.3", "server"), b: 2};

              const expected =
                '[1,{"a":{"type":"reference","origin":"server","value":"0.1.2.3"},"b":2}]';

              assert.equal(serialize(term, true), expected);
            });

            it("not full scope", () => {
              const term = {a: Type.reference("0.1.2.3", "server"), b: 2};

              const expected =
                '[1,{"a":{"type":"reference","value":"0.1.2.3"},"b":2}]';

              assert.equal(serialize(term, false), expected);
            });
          });
        });

        it("not versioned", () => {
          const term = Type.reference("0.1.2.3", "client");

          const expected =
            '{"type":"reference","origin":"client","value":"0.1.2.3"}';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("tuple", () => {
        it("top-level", () => {
          const term = Type.tuple([Type.integer(1), Type.float(1.23)]);

          const expected =
            '[1,{"type":"tuple","data":["__integer__:1","__float__:1.23"]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.tuple([Type.integer(1), Type.float(1.23)]),
            b: 2,
          };

          const expected =
            '[1,{"a":{"type":"tuple","data":["__integer__:1","__float__:1.23"]},"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = Type.tuple([Type.integer(1), Type.float(1.23)]);

          const expected =
            '{"type":"tuple","data":["__integer__:1","__float__:1.23"]}';

          assert.equal(serialize(term, true, false), expected);
        });
      });
    });

    describe("JS terms", () => {
      describe("array", () => {
        it("top-level", () => {
          const term = [123, Type.float(2.34), Type.bitstring([1, 0, 1, 0])];

          const expected =
            '[1,[123,"__float__:2.34",{"type":"bitstring","bits":[1,0,1,0]}]]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: [123, Type.float(2.34), Type.bitstring([1, 0, 1, 0])],
            b: 2,
          };

          const expected =
            '[1,{"a":[123,"__float__:2.34",{"type":"bitstring","bits":[1,0,1,0]}],"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = [123, Type.float(2.34), Type.bitstring([1, 0, 1, 0])];

          const expected =
            '[123,"__float__:2.34",{"type":"bitstring","bits":[1,0,1,0]}]';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("BigInt", () => {
        it("top-level", () => {
          const term = 123n;
          const expected = '[1,"__bigint__:123"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 123n, b: 2};
          const expected = '[1,{"a":"__bigint__:123","b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = 123n;
          const expected = '"__bigint__:123"';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("boolean", () => {
        it("top-level", () => {
          const term = true;
          const expected = "[1,true]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: true, b: 2};
          const expected = '[1,{"a":true,"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = true;
          const expected = "true";

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("float", () => {
        it("top-level", () => {
          const term = 2.34;
          const expected = "[1,2.34]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 1.23, b: 2};
          const expected = '[1,{"a":1.23,"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = 2.34;
          const expected = "2.34";

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("function", () => {
        describe("longhand syntax", () => {
          // prettier-ignore
          const fun = function (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring('a"bc'); return Type.list([integer, binary, param2]); };

          it("top-level", () => {
            const expected = `[1,"__function__:function (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"]`;

            assert.equal(serialize(fun), expected);
          });

          it("nested", () => {
            const term = {a: fun, b: 2};
            const expected = `[1,{"a":"__function__:function (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }","b":2}]`;

            assert.equal(serialize(term), expected);
          });

          it("not versioned", () => {
            const expected = `"__function__:function (param1, param2) { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"`;

            assert.equal(serialize(fun, true, false), expected);
          });
        });

        describe("shorthand syntax", () => {
          // prettier-ignore
          const fun = (param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring('a"bc'); return Type.list([integer, binary, param2]); };

          it("top-level", () => {
            const expected = `[1,"__function__:(param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"]`;

            assert.equal(serialize(fun), expected);
          });

          it("nested", () => {
            const term = {a: fun, b: 2};
            const expected = `[1,{"a":"__function__:(param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }","b":2}]`;

            assert.equal(serialize(term), expected);
          });

          it("not versioned", () => {
            const expected = `"__function__:(param1, param2) => { const integer = Type.integer(param1); const binary = Type.bitstring('a\\"bc'); return Type.list([integer, binary, param2]); }"`;

            assert.equal(serialize(fun, true, false), expected);
          });
        });
      });

      describe("integer", () => {
        it("top-level", () => {
          const term = 234;
          const expected = "[1,234]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 123, b: 2};
          const expected = '[1,{"a":123,"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = 234;
          const expected = "234";

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("null", () => {
        it("top-level", () => {
          const term = null;
          const expected = "[1,null]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: null, b: 2};
          const expected = '[1,{"a":null,"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = null;
          const expected = "null";

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("object", () => {
        it("top-level", () => {
          const term = {a: 1, 'b"cd': 2.34};
          const expected = '[1,{"a":1,"b\\"cd":2.34}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 1, b: {c: 3.45, 'd"ef': "xyz"}};
          const expected = '[1,{"a":1,"b":{"c":3.45,"d\\"ef":"xyz"}}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = {a: 1, b: {c: 3.45, 'd"ef': "xyz"}};
          const expected = '{"a":1,"b":{"c":3.45,"d\\"ef":"xyz"}}';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("string", () => {
        it("top-level", () => {
          const term = 'a"bc';
          const expected = '[1,"a\\"bc"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 'x"yz', b: 2};
          const expected = '[1,{"a":"x\\"yz","b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = 'a"bc';
          const expected = '"a\\"bc"';

          assert.equal(serialize(term, true, false), expected);
        });
      });

      describe("undefined", () => {
        it("top-level", () => {
          const term = undefined;
          const expected = "[1,null]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: undefined, b: 2};
          const expected = '[1,{"a":null,"b":2}]';

          assert.equal(serialize(term), expected);
        });

        it("not versioned", () => {
          const term = undefined;
          const expected = "null";

          assert.equal(serialize(term, true, false), expected);
        });
      });
    });
  });
});
