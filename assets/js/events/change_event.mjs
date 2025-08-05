"use strict";

import Type from "../type.mjs";

export default class ChangeEvent {
  static buildOperationParam(event) {
    const target = event.target;
    let value;

    if (target.type === "checkbox" || target.type === "radio") {
      value = Type.boolean(target.checked);
    } else {
      value = Type.bitstring(target.value);
    }

    return Type.map([[Type.atom("value"), value]]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
