"use strict";

import SubmitEvent from "./submit_event.mjs";
import Type from "../type.mjs";

export default class ChangeEvent {
  // The DOM change event is not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  static buildEventParam(event) {
    const target = event.target;
    const tagName = target.localName;

    // Check if this is a form-level change event by examining currentTarget. Asked through the
    // object's string tag rather than its tag name: a form control named "localName" or "tagName"
    // shadows those properties on the form, and a "form" element inside <svg>, which the HTML
    // parser and the client renderer keep in the SVG namespace, has the local name but isn't a form
    // FormData can read.
    if (
      Object.prototype.toString.call(event.currentTarget) ===
      "[object HTMLFormElement]"
    ) {
      const formEvent = {target: event.currentTarget};
      return SubmitEvent.buildEventParam(formEvent);
    }

    const type = target.type;
    let value;

    if (tagName === "input" && type === "checkbox") {
      value = Type.boolean(target.checked);
    } else if (tagName === "select") {
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
