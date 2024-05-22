"use strict";

export default class HologramRuntimeError extends Error {
  constructor(message) {
    super(message);
    this.name = "HologramRuntimeError";
  }
}
