"use strict";

import DragEvent from "../events/drag_event.mjs";

export default class DropEvent {
  // Prevent the browser's native default. A drop's default opens the dropped file or link in place
  // of the page, which a drop target almost never wants; a binding that does opts out with
  // allow_default.
  static isDefaultAllowed = false;

  static buildEventParam(event) {
    return DragEvent.buildEventParam(event);
  }

  static isEventIgnored(event) {
    return DragEvent.isEventIgnored(event);
  }
}
