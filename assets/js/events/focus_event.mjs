"use strict";

import Type from "../type.mjs";

export default class FocusEvent {
  static isDefaultAllowed = false;

  // TODO: add fields specific to FocusEvent
  static buildOperationParam(_event) {
    return Type.map();
  }

  static isEventIgnored(_event) {
    return false;
  }
}
