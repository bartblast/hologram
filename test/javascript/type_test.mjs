"use strict";

import {
  assert,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import Sequence from "../../assets/js/sequence.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Type", () => {
  describe("actionStruct()", () => {
    it("default values", () => {
      assert.deepStrictEqual(
        Type.actionStruct(),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component.Action")],
          [Type.atom("name"), Type.nil()],
          [Type.atom("params"), Type.map()],
          [Type.atom("target"), Type.nil()],
        ]),
      );
    });

    it("custom values", () => {
      const name = Type.atom("my_action");

      const params = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      const target = Type.bitstring("my_target");

      const result = Type.actionStruct({name, params, target});

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component.Action")],
          [Type.atom("name"), name],
          [Type.atom("params"), params],
          [Type.atom("target"), target],
        ]),
      );
    });
  });

  it("alias()", () => {
    const result = Type.alias("Aaa.Bbb");
    const expected = Type.atom("Elixir.Aaa.Bbb");

    assert.deepStrictEqual(result, expected);
  });

  it("anonymousFunction()", () => {
    Sequence.reset();

    const arity = 3;
    const clauses = ["clause_dummy_1", "clause_dummy_2"];

    const context = contextFixture({
      vars: {a: Type.integer(1), b: Type.integer(2)},
    });

    const result = Type.anonymousFunction(arity, clauses, context);

    const expected = {
      type: "anonymous_function",
      arity: arity,
      capturedFunction: null,
      capturedModule: null,
      clauses: clauses,
      context: context,
      uniqueId: 1,
    };

    assert.deepStrictEqual(result, expected);
  });

  it("atom()", () => {
    const result = Type.atom("test");
    const expected = {type: "atom", value: "test"};

    assert.deepStrictEqual(result, expected);
  });

  describe("bitstring()", () => {
    it("builds bitstring from string value", () => {
      const result = Type.bitstring("abc");

      // ?a == 97 == 0b01100001
      // ?b == 98 == 0b01100010
      // ?c == 99 == 0b01100011

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
              0, 1, 1, 0, 0, 0, 0, 1,
              0, 1, 1, 0, 0, 0, 1, 0,
              0, 1, 1, 0, 0, 0, 1, 1
            ]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds bitstring from segments array", () => {
      const segment1 = Type.bitstringSegment(Type.integer(170), {
        type: "integer",
      });

      const segment2 = Type.bitstringSegment(Type.integer(-22), {
        type: "integer",
      });

      const result = Type.bitstring([segment1, segment2]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
          1, 0, 1, 0, 1, 0, 1, 0,
          1, 1, 1, 0, 1, 0, 1, 0
        ]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds bitstring from bits array", () => {
      const result = Type.bitstring([1, 0, 1, 0]);
      const expected = {type: "bitstring", bits: new Uint8Array([1, 0, 1, 0])};

      assert.deepStrictEqual(result, expected);
    });
  });

  it("bitstringPattern()", () => {
    const segment1 = Type.bitstringSegment(Type.integer(1), {type: "integer"});
    const segment2 = Type.bitstringSegment(Type.integer(2), {type: "integer"});

    const result = Type.bitstringPattern([segment1, segment2]);

    const expected = {
      type: "bitstring_pattern",
      segments: [segment1, segment2],
    };

    assert.deepStrictEqual(result, expected);
  });

  describe("bitstringSegment()", () => {
    it("builds bitstring segment when no modifiers (except type) are given", () => {
      const result = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      const expected = {
        value: {type: "integer", value: 123n},
        type: "integer",
        size: null,
        unit: null,
        signedness: null,
        endianness: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds bitstring segment when all modifiers are given", () => {
      const result = Type.bitstringSegment(Type.integer(123), {
        endianness: "little",
        signedness: "unsigned",
        unit: 3n,
        size: Type.integer(8),
        type: "integer",
      });

      const expected = {
        value: {type: "integer", value: 123n},
        type: "integer",
        size: Type.integer(8),
        unit: 3n,
        signedness: "unsigned",
        endianness: "little",
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds bitstring segment when single modifier (except type) is given", () => {
      const result = Type.bitstringSegment(Type.integer(123), {
        signedness: "unsigned",
        type: "integer",
      });

      const expected = {
        value: {type: "integer", value: 123n},
        type: "integer",
        size: null,
        unit: null,
        signedness: "unsigned",
        endianness: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("raises error if type modifier is not given", () => {
      const expectedMessage =
        "bitstring segment type modifier is not specified";

      assert.throw(
        () => Type.bitstringSegment(Type.integer(123), {}),
        HologramInterpreterError,
        expectedMessage,
      );
    });
  });

  describe("boolean()", () => {
    it("returns boxed true value", () => {
      const result = Type.boolean(true);
      const expected = {type: "atom", value: "true"};

      assert.deepStrictEqual(result, expected);
    });

    it("returns boxed false value", () => {
      const result = Type.boolean(false);
      const expected = {type: "atom", value: "false"};

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("commandStruct()", () => {
    it("default values", () => {
      assert.deepStrictEqual(
        Type.commandStruct(),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component.Command")],
          [Type.atom("name"), Type.nil()],
          [Type.atom("params"), Type.map()],
          [Type.atom("target"), Type.nil()],
        ]),
      );
    });

    it("custom values", () => {
      const name = Type.atom("my_command");

      const params = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      const target = Type.bitstring("my_target");

      const result = Type.commandStruct({name, params, target});

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component.Command")],
          [Type.atom("name"), name],
          [Type.atom("params"), params],
          [Type.atom("target"), target],
        ]),
      );
    });
  });

  describe("componentStruct()", () => {
    it("default values", () => {
      assert.deepStrictEqual(
        Type.componentStruct(),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component")],
          [Type.atom("emitted_context"), Type.map()],
          [Type.atom("next_action"), Type.nil()],
          [Type.atom("next_command"), Type.nil()],
          [Type.atom("next_page"), Type.nil()],
          [Type.atom("state"), Type.map()],
        ]),
      );
    });

    it("custom values", () => {
      const emittedContext = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      const nextAction = Type.actionStruct({name: "my_action"});

      const nextCommand = Type.commandStruct({name: "my_command"});

      const nextPage = Type.tuple([
        Type.alias("MyPage"),
        Type.keywordList([
          [Type.atom("x"), Type.integer(5)],
          [Type.atom("y"), Type.integer(6)],
        ]),
      ]);

      const state = Type.map([
        [Type.atom("c"), Type.integer(3)],
        [Type.atom("d"), Type.integer(4)],
      ]);

      const result = Type.componentStruct({
        emittedContext,
        nextAction,
        nextCommand,
        nextPage,
        state,
      });

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component")],
          [Type.atom("emitted_context"), emittedContext],
          [Type.atom("next_action"), nextAction],
          [Type.atom("next_command"), nextCommand],
          [Type.atom("next_page"), nextPage],
          [Type.atom("state"), state],
        ]),
      );
    });
  });

  it("consPattern()", () => {
    const head = Type.integer(1);
    const tail = Type.list([Type.integer(2), Type.integer(3)]);
    const result = Type.consPattern(head, tail);

    const expected = {type: "cons_pattern", head: head, tail: tail};
    assert.deepStrictEqual(result, expected);
  });

  describe("encodeMapKey()", () => {
    it("encodes boxed anonymous function value as map key", () => {
      Sequence.reset();

      const anonymousFunction = Type.anonymousFunction(
        "dummyArity",
        "dummyClauses",
        "dummyContext",
      );

      const result = Type.encodeMapKey(anonymousFunction);

      assert.equal(result, "anonymous_function(1)");
    });

    it("encodes boxed atom value as map key", () => {
      const atom = Type.atom("abc");
      const result = Type.encodeMapKey(atom);

      assert.equal(result, "atom(abc)");
    });

    it("encodes empty boxed bitstring value as map key", () => {
      const segment = Type.bitstringSegment(Type.integer(0), {
        size: Type.integer(0),
        type: "integer",
      });
      const bitstring = Type.bitstring([segment]);
      const result = Type.encodeMapKey(bitstring);

      assert.equal(result, "bitstring()");
    });

    it("encodes non-empty boxed bitstring value as map key", () => {
      // 170 == 0b10101010

      const segment = Type.bitstringSegment(Type.integer(170), {
        type: "integer",
      });
      const bitstring = Type.bitstring([segment]);
      const result = Type.encodeMapKey(bitstring);

      assert.equal(result, "bitstring(10101010)");
    });

    it("encodes boxed float value as map key", () => {
      const float = Type.float(1.23);
      const result = Type.encodeMapKey(float);

      assert.equal(result, "float(1.23)");
    });

    it("encodes boxed integer value as map key", () => {
      const integer = Type.integer(123);
      const result = Type.encodeMapKey(integer);

      assert.equal(result, "integer(123)");
    });

    it("encodes empty boxed list value as map key", () => {
      const result = Type.encodeMapKey(Type.list());

      assert.equal(result, "list()");
    });

    it("encodes non-empty boxed list value as map key", () => {
      const list = Type.list([Type.integer(1), Type.atom("b")]);
      const result = Type.encodeMapKey(list);

      assert.equal(result, "list(integer(1),atom(b))");
    });

    it("encodes empty boxed map value as map key", () => {
      const result = Type.encodeMapKey(Type.map());

      assert.equal(result, "map()");
    });

    it("encodes non-empty boxed map value as map key", () => {
      const map = Type.map([
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("a"), Type.integer(1)],
      ]);

      const result = Type.encodeMapKey(map);

      assert.equal(result, "map(atom(a):integer(1),atom(b):integer(2))");
    });

    it("encodes empty boxed tuple value as map key", () => {
      const result = Type.encodeMapKey(Type.tuple([]));

      assert.equal(result, "tuple()");
    });

    it("encodes non-empty boxed tuple value as map key", () => {
      const tuple = Type.tuple([Type.integer(1), Type.atom("b")]);
      const result = Type.encodeMapKey(tuple);

      assert.equal(result, "tuple(integer(1),atom(b))");
    });
  });

  it("errorStruct()", () => {
    const result = Type.errorStruct("Aaa.Bbb", "abc");

    const expected = {
      type: "map",
      data: {
        "atom(__exception__)": [Type.atom("__exception__"), Type.boolean(true)],
        "atom(__struct__)": [Type.atom("__struct__"), Type.alias("Aaa.Bbb")],
        "atom(message)": [Type.atom("message"), Type.bitstring("abc")],
      },
    };

    assert.deepStrictEqual(result, expected);
  });

  it("float()", () => {
    const result = Type.float(1.23);
    const expected = {type: "float", value: 1.23};

    assert.deepStrictEqual(result, expected);
  });

  it("functionCapture()", () => {
    Sequence.reset();

    const capturedModule = "MyModule";
    const capturedFunction = "my_fun";
    const arity = 2;
    const clauses = ["clause_dummy_1", "clause_dummy_2"];

    const context = contextFixture({
      module: "Aaa.Bbb",
      vars: {a: Type.integer(1), b: Type.integer(2)},
    });

    const result = Type.functionCapture(
      capturedModule,
      capturedFunction,
      arity,
      clauses,
      context,
    );

    const expected = {
      type: "anonymous_function",
      arity: arity,
      capturedFunction: capturedFunction,
      capturedModule: capturedModule,
      clauses: clauses,
      context: contextFixture({module: "Aaa.Bbb", vars: {}}),
      uniqueId: 1,
    };

    assert.deepStrictEqual(result, expected);
  });

  describe("improperList()", () => {
    it("empty list", () => {
      assert.throw(
        () => Type.improperList([]),
        HologramInterpreterError,
        "improper list must have at least 2 items, received []",
      );
    });

    it("1 item list", () => {
      assert.throw(
        () => Type.improperList([Type.integer(1)]),
        HologramInterpreterError,
        'improper list must have at least 2 items, received ["__integer__:1"]',
      );
    });

    it("2 items list", () => {
      const data = [Type.integer(1), Type.integer(2)];
      const result = Type.improperList(data);
      const expected = {type: "list", data: data, isProper: false};

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("integer()", () => {
    it("returns boxed integer value given JavaScript integer", () => {
      const result = Type.integer(1);
      const expected = {type: "integer", value: 1n};

      assert.deepStrictEqual(result, expected);
    });

    it("returns boxed integer value given JavaScript bigint", () => {
      const result = Type.integer(1n);
      const expected = {type: "integer", value: 1n};

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("isAlias()", () => {
    it("returns true if the term is a module alias", () => {
      const term = Type.alias("Aaa.Bbb");
      assert.isTrue(Type.isAlias(term));
    });

    it("returns false if the term is an atom, but not a module alias", () => {
      const term = Type.atom("Aaa.Bbb");
      assert.isFalse(Type.isAlias(term));
    });

    it("returns false if the term is not an atom", () => {
      const term = Type.bitstring("Aaa.Bbb");
      assert.isFalse(Type.isAlias(term));
    });
  });

  describe("isAnonymousFunction()", () => {
    it("returns true if the term is an anonymous function", () => {
      const term = Type.anonymousFunction(
        "dummyArity",
        "dummyClauses",
        "dummyContext",
      );

      assert.isTrue(Type.isAnonymousFunction(term));
    });

    it("returns false if the term is not an anonymous function", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isAnonymousFunction(term));
    });
  });

  describe("isAtom()", () => {
    it("returns true for boxed atom value", () => {
      const arg = Type.atom("test");
      const result = Type.isAtom(arg);

      assert.isTrue(result);
    });

    it("returns false for values of type other than boxed atom", () => {
      const arg = Type.integer(123);
      const result = Type.isAtom(arg);

      assert.isFalse(result);
    });
  });

  describe("isBinary()", () => {
    it("returns true if the term is a binary bitsting", () => {
      const term = Type.bitstring("abc");
      assert.isTrue(Type.isBinary(term));
    });

    it("returns false if the term is a non-binary bitstring", () => {
      const term = Type.bitstring([0, 1, 0]);
      assert.isFalse(Type.isBinary(term));
    });

    it("returns false if the term is not a bitstring", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isBinary(term));
    });
  });

  describe("isBitstring()", () => {
    it("returns true if the term is a bitstring", () => {
      const term = Type.bitstring("abc");
      assert.isTrue(Type.isBitstring(term));
    });

    it("returns false if the term is not a bitstring", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isBitstring(term));
    });
  });

  describe("isBitstringPattern()", () => {
    it("returns true if the given object is a boxed bitstring pattern", () => {
      const result = Type.isBitstringPattern(Type.bitstringPattern([]));
      assert.isTrue(result);
    });

    it("returns false if the given object is not a boxed bitstring pattern", () => {
      const result = Type.isBitstringPattern(Type.atom("abc"));
      assert.isFalse(result);
    });
  });

  describe("isBoolean()", () => {
    it("returns true for boxed true value", () => {
      const arg = Type.boolean(true);
      const result = Type.isBoolean(arg);

      assert.isTrue(result);
    });

    it("returns true for boxed false value", () => {
      const arg = Type.boolean(false);
      const result = Type.isBoolean(arg);

      assert.isTrue(result);
    });

    it("returns false for boxed nil value", () => {
      const arg = Type.nil();
      const result = Type.isBoolean(arg);

      assert.isFalse(result);
    });

    it("returns false for values which are not boxed booleans", () => {
      const arg = Type.bitstring("true");
      const result = Type.isBoolean(arg);

      assert.isFalse(result);
    });
  });

  describe("isConsPattern()", () => {
    it("returns true if the given object is a boxed cons pattern", () => {
      const head = Type.integer(1);
      const tail = Type.list([Type.integer(2), Type.integer(3)]);
      const result = Type.isConsPattern(Type.consPattern(head, tail));

      assert.isTrue(result);
    });

    it("returns false if the given object is not a boxed cons pattern", () => {
      const result = Type.isConsPattern(Type.atom("abc"));
      assert.isFalse(result);
    });
  });

  describe("isFalse()", () => {
    it("returns true for boxed false value", () => {
      const arg = Type.atom("false");
      const result = Type.isFalse(arg);

      assert.isTrue(result);
    });

    it("returns false for boxed true value", () => {
      const arg = Type.atom("true");
      const result = Type.isFalse(arg);

      assert.isFalse(result);
    });

    it("returns false for values of types other than boxed atom", () => {
      const arg = Type.integer(123);
      const result = Type.isFalse(arg);

      assert.isFalse(result);
    });
  });

  describe("isFalsy()", () => {
    it("returns true for boxed false value", () => {
      const arg = Type.boolean(false);
      const result = Type.isFalsy(arg);

      assert.isTrue(result);
    });

    it("returns true for boxed nil value", () => {
      const arg = Type.nil();
      const result = Type.isFalsy(arg);

      assert.isTrue(result);
    });

    it("returns false for values other than boxed false or boxed nil values", () => {
      const arg = Type.integer(0);
      const result = Type.isFalsy(arg);

      assert.isFalse(result);
    });
  });

  describe("isFloat()", () => {
    it("returns true for boxed float value", () => {
      const result = Type.isFloat(Type.float(1.23));
      assert.isTrue(result);
    });

    it("returns false for values of types other than boxed float", () => {
      const result = Type.isFloat(Type.atom("abc"));
      assert.isFalse(result);
    });
  });

  describe("isImproperList()", () => {
    it("improper list", () => {
      const term = Type.improperList([Type.integer(1), Type.integer(2)]);
      assert.isTrue(Type.isImproperList(term));
    });

    it("proper list", () => {
      const term = Type.list([Type.integer(1), Type.integer(2)]);
      assert.isFalse(Type.isImproperList(term));
    });

    it("not a list", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isImproperList(term));
    });
  });

  describe("isInteger()", () => {
    it("returns true for boxed integer value", () => {
      const result = Type.isInteger(Type.integer(123));
      assert.isTrue(result);
    });

    it("returns false for values of types other than boxed integer", () => {
      const result = Type.isInteger(Type.atom("abc"));
      assert.isFalse(result);
    });
  });

  describe("isIterator()", () => {
    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    it("returns true for a tuple with 3 elements", () => {
      const term = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      assert.isTrue(Type.isIterator(term));
    });

    it("returns false for a tuple with less than 3 elements", () => {
      const term = Type.tuple([Type.integer(1), Type.integer(2)]);
      assert.isFalse(Type.isIterator(term));
    });

    it("returns false for a tuple with more than 3 elements", () => {
      const term = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);

      assert.isFalse(Type.isIterator(term));
    });

    it("returns true for an improper list with specific structure", () => {
      const term = Type.improperList([Type.integer(0), map]);
      assert.isTrue(Type.isIterator(term));
    });

    it("returns false for an improper list with incorrect structure", () => {
      const term = Type.improperList([Type.atom("key"), Type.integer(123)]);
      assert.isFalse(Type.isIterator(term));
    });

    it("returns false for a proper list", () => {
      const term = Type.list([Type.integer(0), map]);
      assert.isFalse(Type.isIterator(term));
    });

    it("returns true for atom 'none'", () => {
      const term = Type.atom("none");
      assert.isTrue(Type.isIterator(term));
    });

    it("returns false for a non-iterator atom", () => {
      const term = Type.atom("not_none");
      assert.isFalse(Type.isIterator(term));
    });

    it("returns false for a term that is not a tuple, a list or an atom", () => {
      const term = Type.integer(123);
      assert.isFalse(Type.isIterator(term));
    });
  });

  describe("isKeywordList()", () => {
    it("empty keyword list", () => {
      const term = Type.keywordList();
      assert.isTrue(Type.isKeywordList(term));
    });

    it("non-empty keyword list", () => {
      const term = Type.keywordList([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      assert.isTrue(Type.isKeywordList(term));
    });

    it("not a keyword list, all items are 2-tuples", () => {
      const term = Type.keywordList([
        [Type.atom("a"), Type.integer(1)],
        [Type.string("b"), Type.integer(2)],
      ]);

      assert.isFalse(Type.isKeywordList(term));
    });

    it("not a keyword list, some items are not 2-tuples", () => {
      const term = Type.keywordList([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2), Type.string("c")],
      ]);

      assert.isFalse(Type.isKeywordList(term));
    });
  });

  describe("isList()", () => {
    it("returns true for boxed list value", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      assert.isTrue(Type.isList(list));
    });

    it("returns false for values of types other than boxed list", () => {
      const result = Type.isList(Type.atom("abc"));
      assert.isFalse(result);
    });
  });

  describe("isMap()", () => {
    it("returns true if the term is a map", () => {
      const term = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      assert.isTrue(Type.isMap(term));
    });

    it("returns false if the term is not a map", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isMap(term));
    });
  });

  describe("isMatchPlaceholder()", () => {
    it("returns true if the given object is a boxed match placeholder", () => {
      const result = Type.isMatchPlaceholder(Type.matchPlaceholder());
      assert.isTrue(result);
    });

    it("returns false if the given object is not a boxed match placeholder", () => {
      const result = Type.isMatchPlaceholder(Type.integer(1));
      assert.isFalse(result);
    });
  });

  describe("isNil()", () => {
    it("returns true for boxed atom with 'nil' value", () => {
      const arg = Type.nil();
      const result = Type.isNil(arg);

      assert.isTrue(result);
    });

    it("returns false for boxed atom with value other than 'nil'", () => {
      const arg = Type.atom("abc");
      const result = Type.isNil(arg);

      assert.isFalse(result);
    });

    it("returns false for values of type other than boxed atom", () => {
      const arg = Type.bitstring("nil");
      const result = Type.isNil(arg);

      assert.isFalse(result);
    });
  });

  describe("isNumber()", () => {
    it("returns true for boxed floats", () => {
      const arg = Type.float(1.23);
      const result = Type.isNumber(arg);

      assert.isTrue(result);
    });

    it("returns true for boxed integers", () => {
      const arg = Type.integer(1);
      const result = Type.isNumber(arg);

      assert.isTrue(result);
    });

    it("returns false for boxed types other than float or integer", () => {
      const arg = Type.atom("abc");
      const result = Type.isNumber(arg);

      assert.isFalse(result);
    });
  });

  describe("isPid()", () => {
    it("returns true if the term is a pid", () => {
      const term = Type.pid("my_node@my_host", [0, 11, 222]);
      assert.isTrue(Type.isPid(term));
    });

    it("returns false if the term is not a pid", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isPid(term));
    });
  });

  describe("isPort()", () => {
    it("returns true if the term is a port", () => {
      const term = Type.port("0.11");
      assert.isTrue(Type.isPort(term));
    });

    it("returns false if the term is not a port", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isPort(term));
    });
  });

  describe("isProperList()", () => {
    it("returns true for proper boxed list", () => {
      const arg = Type.list([Type.integer(1), Type.integer(2)]);
      const result = Type.isProperList(arg);

      assert.isTrue(result);
    });

    it("returns false for improper boxed list", () => {
      const arg = Type.improperList([Type.integer(1), Type.integer(2)]);
      const result = Type.isProperList(arg);

      assert.isFalse(result);
    });

    it("returns false for boxed types other than list", () => {
      const arg = Type.atom("abc");
      const result = Type.isProperList(arg);

      assert.isFalse(result);
    });
  });

  describe("isRange()", () => {
    it("is a range", () => {
      const term = Type.range(123, 234, 345);
      assert.isTrue(Type.isRange(term));
    });

    it("is a struct that is not a range", () => {
      const term = Type.struct("MyStruct", [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      assert.isFalse(Type.isRange(term));
    });

    it("is a map that is not a struct", () => {
      const term = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      assert.isFalse(Type.isRange(term));
    });

    it("is not a map", () => {
      const term = Type.integer(123);
      assert.isFalse(Type.isRange(term));
    });
  });

  describe("isReference()", () => {
    it("returns true if the term is a reference", () => {
      const term = Type.reference("0.1.2.3");
      assert.isTrue(Type.isReference(term));
    });

    it("returns false if the term is not a reference", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isReference(term));
    });
  });

  describe("isStruct()", () => {
    it("not a map", () => {
      assert.isFalse(Type.isStruct(Type.integer(123)));
    });

    it("a map that is not a struct", () => {
      assert.isFalse(
        Type.isStruct(Type.map([[Type.atom("a"), Type.integer(1)]])),
      );
    });

    it("a struct", () => {
      assert.isTrue(
        Type.isStruct(
          Type.struct("Aaa.Bbb", [[Type.atom("a"), Type.integer(1)]]),
        ),
      );
    });
  });

  describe("isTrue()", () => {
    it("returns true for boxed true value", () => {
      const arg = Type.atom("true");
      const result = Type.isTrue(arg);

      assert.isTrue(result);
    });

    it("returns false for boxed false value", () => {
      const arg = Type.atom("false");
      const result = Type.isTrue(arg);

      assert.isFalse(result);
    });

    it("returns false for values of types other than boxed atom", () => {
      const arg = Type.integer(123);
      const result = Type.isTrue(arg);

      assert.isFalse(result);
    });
  });

  describe("isTruthy()", () => {
    it("returns false for boxed false value", () => {
      const arg = Type.boolean(false);
      const result = Type.isTruthy(arg);

      assert.isFalse(result);
    });

    it("returns false for boxed nil value", () => {
      const arg = Type.nil();
      const result = Type.isTruthy(arg);

      assert.isFalse(result);
    });

    it("returns true for values other than boxed false or boxed nil values", () => {
      const arg = Type.integer(0);
      const result = Type.isTruthy(arg);

      assert.isTrue(result);
    });
  });

  describe("isTuple()", () => {
    it("returns true if the term is a tuple", () => {
      const term = Type.tuple([Type.integer(1), Type.integer(2)]);
      assert.isTrue(Type.isTuple(term));
    });

    it("returns false if the term is not a tuple", () => {
      const term = Type.atom("abc");
      assert.isFalse(Type.isTuple(term));
    });
  });

  describe("isVariablePattern()", () => {
    it("returns true if the given object is a boxed variable pattern", () => {
      const result = Type.isVariablePattern(Type.variablePattern("abc"));
      assert.isTrue(result);
    });

    it("returns false if the given object is not a boxed variable pattern", () => {
      const result = Type.isVariablePattern(Type.atom("abc"));
      assert.isFalse(result);
    });
  });

  describe("list()", () => {
    it("empty", () => {
      const result = Type.list();
      const expected = {type: "list", data: [], isProper: true};

      assert.deepStrictEqual(result, expected);
    });

    it("non-empty", () => {
      const data = [Type.integer(1), Type.integer(2)];
      const result = Type.list(data);
      const expected = {type: "list", data: data, isProper: true};

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("keywordList()", () => {
    it("empty", () => {
      assert.deepStrictEqual(Type.keywordList(), Type.list());
    });

    it("non-empty", () => {
      const data = [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ];

      const result = Type.keywordList(data);

      const expected = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("b"), Type.integer(2)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("map()", () => {
    it("returns empty boxed map value", () => {
      const expected = {type: "map", data: {}};

      assert.deepStrictEqual(Type.map(), expected);
    });

    it("returns non-empty boxed map value", () => {
      const inputData = [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ];

      const expectedData = {
        "atom(a)": [Type.atom("a"), Type.integer(1)],
        "atom(b)": [Type.atom("b"), Type.integer(2)],
      };

      const expected = {type: "map", data: expectedData};

      assert.deepStrictEqual(Type.map(inputData), expected);
    });

    it("if the same key appears more than once, the latter (right-most) value is used and the previous values are ignored", () => {
      const inputData = [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("a"), Type.integer(3)],
        [Type.atom("b"), Type.integer(4)],
        [Type.atom("a"), Type.integer(5)],
        [Type.atom("b"), Type.integer(6)],
      ];

      const expectedData = {
        "atom(a)": [Type.atom("a"), Type.integer(5)],
        "atom(b)": [Type.atom("b"), Type.integer(6)],
      };

      const expected = {type: "map", data: expectedData};

      assert.deepStrictEqual(Type.map(inputData), expected);
    });
  });

  it("matchPlaceholder()", () => {
    assert.deepStrictEqual(Type.matchPlaceholder(), {
      type: "match_placeholder",
    });
  });

  it("nil()", () => {
    assert.deepStrictEqual(Type.nil(), Type.atom("nil"));
  });

  describe("maybeNormalizeNumberTerms()", () => {
    it("left is integer, right is integer", () => {
      const term1 = Type.integer(1);
      const term2 = Type.integer(2);
      const result = Type.maybeNormalizeNumberTerms(term1, term2);
      const expected = ["integer", term1, term2];

      assert.deepStrictEqual(result, expected);
    });

    it("left is integer, right is float", () => {
      const term1 = Type.integer(1);
      const term2 = Type.float(2.0);
      const result = Type.maybeNormalizeNumberTerms(term1, term2);
      const expected = ["float", Type.float(1.0), term2];

      assert.deepStrictEqual(result, expected);
    });

    it("left is float, right is integer", () => {
      const term1 = Type.float(1.0);
      const term2 = Type.integer(2);
      const result = Type.maybeNormalizeNumberTerms(term1, term2);
      const expected = ["float", term1, Type.float(2.0)];

      assert.deepStrictEqual(result, expected);
    });

    it("left is float, right is float", () => {
      const term1 = Type.float(1.0);
      const term2 = Type.float(2.0);
      const result = Type.maybeNormalizeNumberTerms(term1, term2);
      const expected = ["float", term1, term2];

      assert.deepStrictEqual(result, expected);
    });
  });

  it("pid()", () => {
    const result = Type.pid("my_node@my_host", [0, 11, 222], "client");

    const expected = {
      type: "pid",
      node: "my_node@my_host",
      origin: "client",
      segments: [0, 11, 222],
    };

    assert.deepStrictEqual(result, expected);
  });

  it("port()", () => {
    const result = Type.port("0.11", "client");
    const expected = {type: "port", origin: "client", value: "0.11"};

    assert.deepStrictEqual(result, expected);
  });

  it("range()", () => {
    const result = Type.range(123, 234, 345);

    const expected = Type.map([
      [Type.atom("__struct__"), Type.alias("Range")],
      [Type.atom("first"), Type.integer(123)],
      [Type.atom("last"), Type.integer(234)],
      [Type.atom("step"), Type.integer(345)],
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("reference()", () => {
    const result = Type.reference("0.1.2.3", "client");
    const expected = {type: "reference", origin: "client", value: "0.1.2.3"};

    assert.deepStrictEqual(result, expected);
  });

  it("string()", () => {
    const result = Type.string("test");
    const expected = {type: "string", value: "test"};

    assert.deepStrictEqual(result, expected);
  });

  it("struct()", () => {
    const data = [
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ];

    const result = Type.struct("Aaa.Bbb", data);

    const expectedData = {
      "atom(__struct__)": [
        Type.atom("__struct__"),
        Type.atom("Elixir.Aaa.Bbb"),
      ],
      "atom(a)": [Type.atom("a"), Type.integer(1)],
      "atom(b)": [Type.atom("b"), Type.integer(2)],
    };

    const expected = {type: "map", data: expectedData};

    assert.deepStrictEqual(result, expected);
  });

  describe("tuple()", () => {
    it("non-empty", () => {
      const data = [Type.integer(1), Type.integer(2)];
      const result = Type.tuple(data);
      const expected = {type: "tuple", data: data};

      assert.deepStrictEqual(result, expected);
    });

    it("empty", () => {
      const result = Type.tuple();
      const expected = {type: "tuple", data: []};

      assert.deepStrictEqual(result, expected);
    });
  });

  it("variablePattern()", () => {
    const result = Type.variablePattern("test");
    const expected = {type: "variable_pattern", name: "test"};

    assert.deepStrictEqual(result, expected);
  });

  // IMPORTANT!
  // Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/type_test.exs
  // Always update both together.
  describe("consistency tests", () => {
    it("action struct", () => {
      assert.deepStrictEqual(
        Type.actionStruct(),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component.Action")],
          [Type.atom("name"), Type.nil()],
          [Type.atom("params"), Type.map()],
          [Type.atom("target"), Type.nil()],
        ]),
      );
    });

    it("command struct", () => {
      assert.deepStrictEqual(
        Type.commandStruct(),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component.Command")],
          [Type.atom("name"), Type.nil()],
          [Type.atom("params"), Type.map()],
          [Type.atom("target"), Type.nil()],
        ]),
      );
    });

    it("component struct", () => {
      assert.deepStrictEqual(
        Type.componentStruct(),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Component")],
          [Type.atom("emitted_context"), Type.map()],
          [Type.atom("next_action"), Type.nil()],
          [Type.atom("next_command"), Type.nil()],
          [Type.atom("next_page"), Type.nil()],
          [Type.atom("state"), Type.map()],
        ]),
      );
    });
  });
});
