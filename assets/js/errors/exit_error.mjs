"use strict";

export default class HologramExitError extends Error {
  constructor(reason) {
    super("");

    this.name = "HologramExitError";
    this.reason = reason;
    this.message = `exit with reason: ${JSON.stringify(reason)}`;
  }
}
