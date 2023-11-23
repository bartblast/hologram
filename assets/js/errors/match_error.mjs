"use strict";

export default class HologramMatchError extends Error {
  constructor(value) {
    super("");

    this.name = "HologramMatchError";
    this.value = value;
  }
}
