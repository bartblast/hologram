"use strict";

export default class Sequence {
  // Made public to make tests easier
  static value = 0;

  static next() {
    $.value += 1;
    return $.value;
  }

  static reset() {
    $.value = 0;
  }
}

const $ = Sequence;
