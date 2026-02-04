"use strict";

export default class Sequence {
  // Made public to make tests easier
  value = 0;

  next() {
    return ++this.value;
  }

  reset() {
    this.value = 0;
  }
}
