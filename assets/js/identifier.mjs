// Based on Elixir Hologram.Identifier

"use strict";

import Bitstring from "./bitstring.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

const RESERVED_ATOM_HINT = "nil, true and false can't be in an identifier";

// An identifier names something, like a channel or a key: an atom, or a tuple of an atom followed
// by one or more integers, strings or atoms. None of its atoms is nil, true or false, and its
// strings are valid UTF-8.
//
// WARNING: must match Hologram.Identifier on the server.
export default class Identifier {
  // Based on check/1
  //
  // Returns null when the value is an identifier, or {hint}, where the hint says why the value
  // isn't one, or is null when the value isn't shaped like one at all. The first problem found
  // decides the hint: the tuple's size, then its first element, then the elements after it, from
  // left to right.
  static check(value) {
    if ($.#isReservedAtom(value)) {
      return {hint: RESERVED_ATOM_HINT};
    }

    if (Type.isAtom(value)) {
      return null;
    }

    if (!Type.isTuple(value)) {
      return {hint: null};
    }

    if (value.data.length < 2) {
      return {
        hint: "an identifier tuple holds an atom and at least one more value",
      };
    }

    const [tag, ...rest] = value.data;

    if ($.#isReservedAtom(tag)) {
      return {hint: RESERVED_ATOM_HINT};
    }

    if (!Type.isAtom(tag)) {
      return {hint: "an identifier tuple starts with an atom"};
    }

    for (const element of rest) {
      const hint = $.#valueHint(element);

      if (hint !== null) {
        return {hint};
      }
    }

    return null;
  }

  // Based on message/3
  //
  // The message of an error raised for a value that isn't what was expected, in the format shared
  // by everything that takes an identifier.
  static message(expectation, value, hint) {
    const text = `${expectation}, got: ${Interpreter.inspect(value)}`;

    return hint === null ? text : `${text} - ${hint}`;
  }

  // Based on validate!/2
  //
  // Returns the given value if it's an identifier, or raises ArgumentError whose message starts
  // with the given expectation.
  static validate(value, expectation) {
    const result = $.check(value);

    if (result !== null) {
      Interpreter.raiseArgumentError(
        $.message(expectation, value, result.hint),
      );
    }

    return value;
  }

  static #isReservedAtom(value) {
    return Type.isNil(value) || Type.isBoolean(value);
  }

  // Based on value_hint/1
  //
  // Why a value after an identifier tuple's atom can't be there, or null when it can.
  static #valueHint(value) {
    if ($.#isReservedAtom(value)) {
      return RESERVED_ATOM_HINT;
    }

    if (Type.isAtom(value) || Type.isInteger(value)) {
      return null;
    }

    if (Type.isBinary(value)) {
      return Bitstring.isText(value) ? null : "strings must be valid UTF-8";
    }

    return "an identifier tuple holds only integers, strings and atoms after its atom";
  }
}

const $ = Identifier;
