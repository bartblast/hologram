"use strict";

import Type from "../type.mjs";

export default class FocusEvent {
  // The DOM focus and blur events are not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  // TODO: add fields specific to FocusEvent
  static buildOperationParam(_event) {
    return Type.map();
  }

  static isEventIgnored(_event) {
    return false;
  }
}
