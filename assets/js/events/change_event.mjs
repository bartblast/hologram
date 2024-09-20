"use strict";

import Type from "../type.mjs";

export default class ChangeEvent {
  static buildOperationParam(event) {
    return Type.map([[Type.atom("value"), Type.bitstring(event.target.value)]]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
