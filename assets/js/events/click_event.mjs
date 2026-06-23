"use strict";

import PointerEvent from "./pointer_event.mjs";

export default class ClickEvent {
  static isDefaultAllowed = false;

  static buildOperationParam(event) {
    return PointerEvent.buildOperationParam(event);
  }

  // A modified click (ctrl, meta, or shift) asks for the browser's native navigation - open in
  // a new tab or window - so the framework steps aside and lets the default happen instead of
  // dispatching. The button is not checked: the click event fires only for the primary button
  // (others fire auxclick, which Hologram does not bind).
  static isEventIgnored(event) {
    if (event.ctrlKey || event.metaKey || event.shiftKey) {
      return true;
    }

    return false;
  }
}
