"use strict";

import Type from "../type.mjs";

export default class SubmitEvent {
  static buildOperationParam(event) {
    const formData = new FormData(event.target);

    const mapData = [...formData.entries()].map(([name, value]) => [
      Type.bitstring(name),
      Type.bitstring(value),
    ]);

    return Type.map(mapData);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
