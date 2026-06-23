"use strict";

import Type from "../type.mjs";

export default class InputEvent {
  // The DOM input event is not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    return Type.map([[Type.atom("value"), Type.bitstring(event.target.value)]]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
