"use strict";

import Type from "../type.mjs";

export default class ChangeEvent {
  static buildOperationParam(event) {
    const target = event.target;
    const type = target.type;
    const tagName = target.tagName;
    let value;

    if (tagName === "INPUT" && (type === "checkbox" || type === "radio")) {
      value = Type.boolean(target.checked);
    } else if (tagName === "SELECT") {
      if (target.multiple) {
        const selectedOptions = Array.from(target.selectedOptions).map(
          (option) => option.value,
        );
        value = Type.list(
          selectedOptions.map((optionValue) => Type.bitstring(optionValue)),
        );
      } else {
        value = Type.bitstring(target.value);
      }
    } else {
      value = Type.bitstring(target.value);
    }

    return Type.map([[Type.atom("value"), value]]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
