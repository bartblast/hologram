"use strict";

import Type from "../type.mjs";

export default class SubmitEvent {
  static buildOperationParam(event) {
    const form = event.target;
    const formData = new FormData(form);

    const mapData = [...formData.entries()].map(([name, value]) => {
      const element = form.elements[name];

      if (element.tagName === "INPUT" && element.type === "checkbox") {
        // Note: FormData only includes checked checkboxes
        // Since this element appears in FormData, it means it's checked
        return [Type.bitstring(name), Type.boolean(true)];
      }

      return [Type.bitstring(name), Type.bitstring(value)];
    });

    return Type.map(mapData);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
