"use strict";

import PointerEvent from "./pointer_event.mjs";

export default class ClickEvent {
  // Allow the browser's native default. A click lands mostly on buttons and other elements with no
  // native action (preventing is a no-op), or on elements whose native action you want - following
  // a link, toggling a checkbox, expanding a <details>, opening a file picker. Only the Link
  // component needs the default suppressed for client-side navigation, and it opts in with
  // prevent_default.
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    return PointerEvent.buildOperationParam(event);
  }

  // A modified click (alt, ctrl, meta, or shift) asks for the browser's native action - open in a
  // new tab or window, download the target - so the framework steps aside and lets the default
  // happen instead of dispatching. The button is not checked: the click event fires only for the
  // primary button (others fire auxclick, which Hologram does not bind).
  static isEventIgnored(event) {
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) {
      return true;
    }

    return false;
  }
}
