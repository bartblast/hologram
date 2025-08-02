"use strict";

import Type from "../type.mjs";

export default class ChangeEvent {
  static buildOperationParam(event) {
    let value = Type.bitstring(event.target.checked);

    if (event.target.type === "checkbox") {
      value = Type.boolean(event.target.checked);
    }

    return Type.map([[Type.atom("value"), value]]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
