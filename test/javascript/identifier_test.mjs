"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
} from "./support/helpers.mjs";

import Bitstring from "../../assets/js/bitstring.mjs";
import Identifier from "../../assets/js/identifier.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

const expectation = "a thing must be an identifier";

describe("Identifier", () => {
  describe("check()", () => {
    it("an atom", () => {
      assert.isNull(Identifier.check(Type.atom("search")));
    });

    it("a module", () => {
      assert.isNull(Identifier.check(Type.alias("MyApp.Room")));
    });

    it("a tuple with an atom value", () => {
      assert.isNull(
        Identifier.check(Type.tuple([Type.atom("tag"), Type.atom("value")])),
      );
    });

    it("a tuple with an integer value", () => {
      assert.isNull(
        Identifier.check(Type.tuple([Type.atom("message"), Type.integer(42)])),
      );
    });

    it("a tuple with a string value", () => {
      assert.isNull(
        Identifier.check(
          Type.tuple([Type.atom("room"), Type.bitstring("lounge")]),
        ),
      );
    });

    it("a tuple with several values of mixed types", () => {
      assert.isNull(
        Identifier.check(
          Type.tuple([
            Type.atom("cell"),
            Type.atom("a"),
            Type.integer(1),
            Type.bitstring("b"),
          ]),
        ),
      );
    });

    it("nil", () => {
      assert.deepStrictEqual(Identifier.check(Type.nil()), {
        hint: "nil, true and false can't be in an identifier",
      });
    });

    it("true", () => {
      assert.deepStrictEqual(Identifier.check(Type.boolean(true)), {
        hint: "nil, true and false can't be in an identifier",
      });
    });

    it("false", () => {
      assert.deepStrictEqual(Identifier.check(Type.boolean(false)), {
        hint: "nil, true and false can't be in an identifier",
      });
    });

    it("an empty tuple", () => {
      assert.deepStrictEqual(Identifier.check(Type.tuple()), {
        hint: "an identifier tuple holds an atom and at least one more value",
      });
    });

    it("a tuple of one atom", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.atom("room")])),
        {hint: "an identifier tuple holds an atom and at least one more value"},
      );
    });

    it("a tuple of one value that isn't an atom", () => {
      assert.deepStrictEqual(Identifier.check(Type.tuple([Type.integer(1)])), {
        hint: "an identifier tuple holds an atom and at least one more value",
      });
    });

    it("a tuple of one nil", () => {
      assert.deepStrictEqual(Identifier.check(Type.tuple([Type.nil()])), {
        hint: "an identifier tuple holds an atom and at least one more value",
      });
    });

    it("a tuple whose first element is nil", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.nil(), Type.integer(1)])),
        {hint: "nil, true and false can't be in an identifier"},
      );
    });

    it("a tuple whose first element is true", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.boolean(true), Type.integer(1)])),
        {hint: "nil, true and false can't be in an identifier"},
      );
    });

    it("a tuple whose first element is false", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.boolean(false), Type.integer(1)])),
        {hint: "nil, true and false can't be in an identifier"},
      );
    });

    it("a tuple whose first element is a string", () => {
      assert.deepStrictEqual(
        Identifier.check(
          Type.tuple([Type.bitstring("room"), Type.integer(42)]),
        ),
        {hint: "an identifier tuple starts with an atom"},
      );
    });

    it("a tuple whose first element is a string and whose value is nil", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.bitstring("room"), Type.nil()])),
        {hint: "an identifier tuple starts with an atom"},
      );
    });

    it("a tuple with a nil value", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.atom("room"), Type.nil()])),
        {hint: "nil, true and false can't be in an identifier"},
      );
    });

    it("a tuple with a true value", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.atom("room"), Type.boolean(true)])),
        {hint: "nil, true and false can't be in an identifier"},
      );
    });

    it("a tuple with a false value", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.atom("room"), Type.boolean(false)])),
        {hint: "nil, true and false can't be in an identifier"},
      );
    });

    it("a tuple with a float value", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.tuple([Type.atom("room"), Type.float(1.5)])),
        {
          hint: "an identifier tuple holds only integers, strings and atoms after its atom",
        },
      );
    });

    it("a tuple with a map value", () => {
      assert.deepStrictEqual(
        Identifier.check(
          Type.tuple([
            Type.atom("room"),
            Type.map([[Type.atom("a"), Type.integer(1)]]),
          ]),
        ),
        {
          hint: "an identifier tuple holds only integers, strings and atoms after its atom",
        },
      );
    });

    it("a tuple with a list value", () => {
      assert.deepStrictEqual(
        Identifier.check(
          Type.tuple([Type.atom("room"), Type.list([Type.integer(1)])]),
        ),
        {
          hint: "an identifier tuple holds only integers, strings and atoms after its atom",
        },
      );
    });

    it("a tuple with a tuple value", () => {
      assert.deepStrictEqual(
        Identifier.check(
          Type.tuple([
            Type.atom("room"),
            Type.tuple([Type.atom("a"), Type.integer(1)]),
          ]),
        ),
        {
          hint: "an identifier tuple holds only integers, strings and atoms after its atom",
        },
      );
    });

    it("a tuple with a string value that isn't valid UTF-8", () => {
      assert.deepStrictEqual(
        Identifier.check(
          Type.tuple([Type.atom("doc"), Bitstring.fromBytes([255])]),
        ),
        {hint: "strings must be valid UTF-8"},
      );
    });

    it("a tuple with a nil value before a float value", () => {
      assert.deepStrictEqual(
        Identifier.check(
          Type.tuple([Type.atom("room"), Type.nil(), Type.float(1.5)]),
        ),
        {hint: "nil, true and false can't be in an identifier"},
      );
    });

    it("a tuple with a float value before a nil value", () => {
      assert.deepStrictEqual(
        Identifier.check(
          Type.tuple([Type.atom("room"), Type.float(1.5), Type.nil()]),
        ),
        {
          hint: "an identifier tuple holds only integers, strings and atoms after its atom",
        },
      );
    });

    it("a string", () => {
      assert.deepStrictEqual(Identifier.check(Type.bitstring("room")), {
        hint: null,
      });
    });

    it("an integer", () => {
      assert.deepStrictEqual(Identifier.check(Type.integer(42)), {hint: null});
    });

    it("a float", () => {
      assert.deepStrictEqual(Identifier.check(Type.float(1.5)), {hint: null});
    });

    it("a list", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.list([Type.atom("room"), Type.integer(42)])),
        {hint: null},
      );
    });

    it("a map", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.map([[Type.atom("id"), Type.integer(42)]])),
        {hint: null},
      );
    });

    it("a pid", () => {
      assert.deepStrictEqual(
        Identifier.check(Type.pid("nonode@nohost", [0, 11, 222], "server")),
        {hint: null},
      );
    });
  });

  describe("message()", () => {
    it("with a hint", () => {
      assert.equal(
        Identifier.message(
          expectation,
          Type.tuple([Type.atom("room"), Type.nil()]),
          "nil, true and false can't be in an identifier",
        ),
        "a thing must be an identifier, got: {:room, nil} - nil, true and false can't be in an identifier",
      );
    });

    it("without a hint", () => {
      assert.equal(
        Identifier.message(expectation, Type.float(1.5), null),
        "a thing must be an identifier, got: 1.5",
      );
    });
  });

  describe("validate()", () => {
    it("returns an atom", () => {
      const value = Type.atom("search");

      assert.equal(Identifier.validate(value, expectation), value);
    });

    it("returns a tuple", () => {
      const value = Type.tuple([Type.atom("message"), Type.integer(42)]);

      assert.equal(Identifier.validate(value, expectation), value);
    });

    it("raises with the hint for a value with one", () => {
      assertBoxedError(
        () =>
          Identifier.validate(
            Type.tuple([Type.atom("room"), Type.nil()]),
            expectation,
          ),
        "ArgumentError",
        "a thing must be an identifier, got: {:room, nil} - nil, true and false can't be in an identifier",
      );
    });

    it("raises without a hint for a value without one", () => {
      assertBoxedError(
        () => Identifier.validate(Type.bitstring("room"), expectation),
        "ArgumentError",
        'a thing must be an identifier, got: "room"',
      );
    });
  });
});
