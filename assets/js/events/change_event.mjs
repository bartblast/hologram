"use strict";

import SubmitEvent from "./submit_event.mjs";
import Type from "../type.mjs";

export default class ChangeEvent {
  static buildOperationParam(event) {
    const target = event.target;
    const tagName = target.tagName;

    // Check if this is a form-level change event by examining currentTarget
    if (event.currentTarget.tagName === "FORM") {
      const formEvent = {target: event.currentTarget};
      return SubmitEvent.buildOperationParam(formEvent);
    }

    const type = target.type;
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
