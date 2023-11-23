"use strict";

export default class HologramInterpreterError extends Error {
  constructor(message) {
    super(message);
    this.name = "HologramInterpreterError";
  }
}
