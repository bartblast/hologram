"use strict";

export class HologramNotImplementedError extends Error {
  constructor(message) {
    super(message);
    this.name = "HologramNotImplementedError";
  }
}

export class HologramRuntimeError extends Error {
  constructor(message) {
    super(message);
    this.name = "HologramRuntimeError";
  }
}