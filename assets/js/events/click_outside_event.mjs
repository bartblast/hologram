"use strict";

import PointerEvent from "./pointer_event.mjs";

export default class ClickOutsideEvent {
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    return PointerEvent.buildOperationParam(event);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
