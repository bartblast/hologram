"use strict";

import PointerEvent from "./pointer_event.mjs";

export default class ClickOutsideEvent {
  static isDefaultAllowed = true;

  static buildEventParam(event) {
    return PointerEvent.buildEventParam(event);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
