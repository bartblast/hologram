"use strict";

import Type from "../type.mjs";

export default class InputEvent {
  static isDefaultAllowed = false;

  static buildOperationParam(event) {
    return Type.map([[Type.atom("value"), Type.bitstring(event.target.value)]]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
