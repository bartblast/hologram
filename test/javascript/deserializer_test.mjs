"use strict";

import {
  assert,
  contextFixture,
  defineRuntimeGlobals,
} from "./support/helpers.mjs";

import Deserializer from "../../assets/js/deserializer.mjs";
import Erlang_Re from "../../assets/js/erlang/re.mjs";
import ERTS from "../../assets/js/erts.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import NodeTable from "../../assets/js/erts/node_table.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

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

        // The clauses the capture had when it was serialized are not what comes back: the
        // deserialized capture gets one clause calling the named function, the way
        // :erlang.make_fun/3 builds one, so that it can be called.
        describe("capture", () => {
          const assertCapture = (deserialized, capturedModule) => {
            assert.equal(deserialized.capturedModule, capturedModule);
            assert.equal(deserialized.capturedFunction, "reverse");
            assert.equal(deserialized.arity, 1);
            assert.equal(deserialized.clauses.length, 1);

            assert.deepStrictEqual(
              deserialized.context,
              Interpreter.buildContext(),
            );

            const callResult = Interpreter.callAnonymousFunction(deserialized, [
              Type.list([Type.integer(1), Type.integer(2)]),
            ]);

            assert.deepStrictEqual(
              callResult,
              Type.list([Type.integer(2), Type.integer(1)]),
            );
          };

          const elixirTerm = Type.functionCapture(
            "Enum",
            "reverse",
            1,
            [],
            context,
          );

          const erlangTerm = Type.functionCapture(
            ":lists",
            "reverse",
            1,
            [],
            context,
          );

          it("Elixir module, top-level", () => {
            const deserialized = deserialize(serialize(elixirTerm, "server"));
            assertCapture(deserialized, "Enum");
          });

          it("Elixir module, nested", () => {
            const deserialized = deserialize(
              serialize({x: elixirTerm}, "server"),
            );

            assertCapture(deserialized.x, "Enum");
          });

          it("Erlang module, top-level", () => {
            const deserialized = deserialize(serialize(erlangTerm, "server"));
            assertCapture(deserialized, ":lists");
          });

          it("Erlang module, nested", () => {
            const deserialized = deserialize(
              serialize({x: erlangTerm}, "server"),
            );

            assertCapture(deserialized.x, ":lists");
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

      describe("Regex struct", () => {
        const buildRef = (seed) =>
          Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [seed, 2, 3]);

        const buildRegexStruct = (rePattern, source, opts) =>
          Type.map([
            [Type.atom("__struct__"), Type.atom("Elixir.Regex")],
            [Type.atom("opts"), opts],
            [Type.atom("re_pattern"), rePattern],
            [Type.atom("source"), Type.bitstring(source)],
          ]);

        const buildRePattern = (ref) =>
          Type.tuple([
            Type.atom("re_pattern"),
            Type.integer(1),
            Type.integer(0),
            Type.integer(0),
            ref,
          ]);

        it("deserializes to the sent struct", () => {
          const ref = buildRef(101);

          const term = buildRegexStruct(
            buildRePattern(ref),
            "a(b+)",
            Type.list(),
          );

          const deserialized = deserialize(serialize(term));

          assert.isTrue(Interpreter.isStrictlyEqual(deserialized, term));
        });

        it("registers the pattern under the incoming ref", () => {
          const ref = buildRef(102);

          const term = buildRegexStruct(
            buildRePattern(ref),
            "a(b+)",
            Type.list(),
          );

          deserialize(serialize(term));

          const registryEntry = ERTS.regexPatternRegistry.get(ref);

          assert.isNotNull(registryEntry);
          assert.equal(registryEntry.captureCount, 1);
        });

        it("the registered pattern is runnable", () => {
          const ref = buildRef(103);

          const term = buildRegexStruct(
            buildRePattern(ref),
            "a(b+)",
            Type.list(),
          );

          deserialize(serialize(term));

          const result = Erlang_Re["run/3"](
            Type.bitstring("abbc"),
            buildRePattern(ref),
            Type.list(),
          );

          assert.deepEqual(
            result,
            Type.tuple([
              Type.atom("match"),
              Type.list([
                Type.tuple([Type.integer(0), Type.integer(3)]),
                Type.tuple([Type.integer(1), Type.integer(2)]),
              ]),
            ]),
          );
        });

        it("applies the compile options", () => {
          const ref = buildRef(104);

          const term = buildRegexStruct(
            buildRePattern(ref),
            "ab",
            Type.list([Type.atom("caseless")]),
          );

          deserialize(serialize(term));

          const result = Erlang_Re["run/3"](
            Type.bitstring("AB"),
            buildRePattern(ref),
            Type.list(),
          );

          assert.deepEqual(
            result,
            Type.tuple([
              Type.atom("match"),
              Type.list([Type.tuple([Type.integer(0), Type.integer(2)])]),
            ]),
          );
        });

        it("skips registration for an already known ref", () => {
          const ref = buildRef(105);

          const existingEntry = {marker: "existing entry"};

          ERTS.regexPatternRegistry.put(ref, existingEntry);

          const term = buildRegexStruct(
            buildRePattern(ref),
            "a(b+)",
            Type.list(),
          );

          deserialize(serialize(term));

          assert.strictEqual(ERTS.regexPatternRegistry.get(ref), existingEntry);
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

    // Data stored by an earlier release starts with its own version, and reads by that version's
    // rules: an "s" value was a JavaScript string in version 3 and is a string in version 4.
    describe("format version", () => {
      it("version 4, s marks a string", () => {
        assert.deepStrictEqual(
          deserialize('[4,"sabc"]'),
          Type.bitstring("abc"),
        );
      });

      it("version 4, s marks a string, beyond ASCII", () => {
        assert.deepStrictEqual(
          deserialize('[4,"szażółć 🎉"]'),
          Type.bitstring("zażółć 🎉"),
        );
      });

      it("version 4, s marks a string, empty", () => {
        assert.deepStrictEqual(deserialize('[4,"s"]'), Type.bitstring(""));
      });

      it("version 4, j marks a JavaScript string", () => {
        assert.equal(deserialize('[4,"jabc"]'), "abc");
      });

      it("version 4, nested", () => {
        assert.deepStrictEqual(deserialize('[4,{"a":"sabc","b":"jxyz"}]'), {
          a: Type.bitstring("abc"),
          b: "xyz",
        });
      });

      it("version 3, s marks a JavaScript string", () => {
        assert.equal(deserialize('[3,"sabc"]'), "abc");
      });

      it("version 3, reference", () => {
        const serialized =
          '[3,{"t":"r","n":"snonode@nohost","c":0,"i":[3,2,1]}]';

        assert.deepStrictEqual(
          deserialize(serialized),
          Type.reference("nonode@nohost", 0, [3, 2, 1]),
        );
      });

      it("already-parsed array, top-level", () => {
        assert.deepStrictEqual(deserialize([4, "sabc"]), Type.bitstring("abc"));
      });

      it("already-parsed array, nested in a collection", () => {
        assert.deepStrictEqual(
          deserialize([4, {t: "t", d: ["i1", {t: "l", d: ["sabc"]}]}]),
          Type.tuple([Type.integer(1), Type.list([Type.bitstring("abc")])]),
        );
      });

      it("already-parsed array, nested in an object", () => {
        assert.deepStrictEqual(deserialize([4, {a: "sabc", b: "jxyz"}]), {
          a: Type.bitstring("abc"),
          b: "xyz",
        });
      });

      it("already-parsed array, version 3", () => {
        assert.equal(deserialize([3, "sabc"]), "abc");
      });
    });

    // The strings here are what Hologram.Runtime.Serializer writes for the same terms.
    describe("terms the server serializes", () => {
      // Looking a reference up registers its node in the node table, which other tests read.
      afterEach(() => {
        NodeTable.reset();
      });

      it("pid", () => {
        const serialized = `[4,"pnonode@nohost${Serializer.DELIMITER}0,11,222${Serializer.DELIMITER}server"]`;

        assert.deepStrictEqual(
          deserialize(serialized),
          Type.pid("nonode@nohost", [0, 11, 222], "server"),
        );
      });

      it("reference", () => {
        const serialized =
          '[4,{"t":"r","n":"jnonode@nohost","c":0,"i":[3,2,1]}]';

        assert.deepStrictEqual(
          deserialize(serialized),
          Type.reference("nonode@nohost", 0, [3, 2, 1]),
        );
      });

      it("Regex struct, registered under the reference it carries", () => {
        const serialized =
          '[4,{"t":"m","d":[["are_pattern",{"t":"t","d":["are_pattern","i1","i1","i0",{"t":"r","n":"jnonode@nohost","c":0,"i":[80213,907673603,1311398366]}]}],["aopts",{"t":"l","d":["aunicode","aucp","acaseless"]}],["asource","s(a)b"],["a__struct__","aElixir.Regex"]]}]';

        const regex = deserialize(serialized);

        assert.isTrue(Type.isStruct(regex, "Regex"));

        const rePattern =
          regex.data[Type.encodeMapKey(Type.atom("re_pattern"))][1];

        assert.isNotNull(ERTS.regexPatternRegistry.lookupByTerm(rePattern));

        const runResult = Erlang_Re["run/2"](Type.bitstring("xAB"), rePattern);

        assert.deepStrictEqual(
          runResult,
          Type.tuple([
            Type.atom("match"),
            Type.list([
              Type.tuple([Type.integer(1), Type.integer(2)]),
              Type.tuple([Type.integer(1), Type.integer(1)]),
            ]),
          ]),
        );
      });
    });
  });
});
