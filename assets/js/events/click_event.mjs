"use strict";

import MouseEvent from "./mouse_event.mjs";

export default class ClickEvent {
  static buildOperationParam(event) {
    // TODO: change to PointerEvent when Firefox and Safari bugs are fixed:
    // See: https://stackoverflow.com/a/76900433
    // See: https://bugzilla.mozilla.org/show_bug.cgi?id=1675847
    // See: https://bugs.webkit.org/show_bug.cgi?id=218665
    return MouseEvent.buildOperationParam(event);
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
