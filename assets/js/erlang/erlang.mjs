"use strict";

import Type from "../type.mjs";
import Interpreter from "../interpreter.mjs";

export default class Erlang {
  // start: =:=/2
  static $61$58$61(left, right) {
    return Type.boolean(Interpreter.isStrictlyEqual(left, right));
  }
  // end: =:=/2

  // start: hd/1
  static hd(list) {
    return Interpreter.head(list);
  }
  // end: hd/1

  // start: is_atom/1
  static is_atom(term) {
    return Type.boolean(Type.isAtom(term));
  }
  // end: is_atom/1

  // start: is_float/1
  static is_float(term) {
    return Type.boolean(Type.isFloat(term));
  }
  // end: is_float/1

  // start: is_integer/1
  static is_integer(term) {
    return Type.boolean(Type.isInteger(term));
  }
  // end: is_integer/1

  // start: is_number/1
  static is_number(term) {
    return Type.boolean(Type.isNumber(term));
  }
  // end: is_number/1

  // start: length/1
  static length(list) {
    return Type.integer(Interpreter.count(list));
  }
  // end: length/1

  // start: tl/1
  static tl(list) {
    return Interpreter.tail(list);
  }
  // end: tl/1
}
