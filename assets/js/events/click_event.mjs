"use strict";

import PointerEvent from "./pointer_event.mjs";

export default class ClickEvent {
  static buildOperationParam(event) {
    return PointerEvent.buildOperationParam(event);
  }

  // See: https://stackoverflow.com/a/20087506/13040586
  static isEventIgnored(event) {
    if (
      event.ctrlKey ||
      event.metaKey ||
      event.shiftKey ||
      event.button === 1
    ) {
      return true;
    }

    return false;
  }
}
