"use strict";

export default class Sequence {
  static value = 0;

  static next() {
    Sequence.value += 1;
    return Sequence.value;
  }
}
