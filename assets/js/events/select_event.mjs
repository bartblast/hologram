"use strict";

import Type from "../type.mjs";

export default class SelectEvent {
  static buildOperationParam(event) {
    const value = event.target.value.substring(
      event.target.selectionStart,
      event.target.selectionEnd,
    );

    return Type.map([[Type.atom("value"), Type.bitstring(value)]]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
