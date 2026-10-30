"use strict";

import Bitstring from "../bitstring.mjs";
import Type from "../type.mjs";

// Maps each modifier key name to the live event's corresponding boolean property.
const MODIFIER_FLAGS = {
  alt: "altKey",
  ctrl: "ctrlKey",
  meta: "metaKey",
  shift: "shiftKey",
};

export default class KeyboardEvent {
  // Allow the browser's default action (typing, caret movement, etc.); an
  // automatic preventDefault would block keyboard input.
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    return Type.map([
      [Type.atom("alt_key"), Type.boolean(event.altKey)],
      [Type.atom("code"), Type.bitstring(event.code)],
      [Type.atom("ctrl_key"), Type.boolean(event.ctrlKey)],
      [Type.atom("key"), Type.bitstring(event.key)],
      [Type.atom("meta_key"), Type.boolean(event.metaKey)],
      [Type.atom("repeat"), Type.boolean(event.repeat)],
      [Type.atom("shift_key"), Type.boolean(event.shiftKey)],
    ]);
  }

  // A keydown or keyup with no key is a browser artifact, not a keypress (Chromium fires a bare
  // Event named keydown before it autofills a field and one named keyup after it). Such an event
  // also lacks code and the modifier flags, so no usable param can be built from it.
  static isEventIgnored(event) {
    return typeof event.key !== "string";
  }

  // Decides whether a key filter (the values of a {:key, values} modifier) matches a live
  // event. Each value is either a modifier key, checked against the event's boolean flag, or
  // the key itself, compared against the lowercased event.key (already the canonical form).
  static matchesKeyFilter(filterValues, event) {
    // An event with no key matches no filter.
    if (typeof event.key !== "string") {
      return false;
    }

    const eventKey = event.key.toLowerCase();

    return filterValues.data.every((boxedValue) => {
      const value = Bitstring.toText(boxedValue);
      const flag = MODIFIER_FLAGS[value];

      return flag ? event[flag] === true : value === eventKey;
    });
  }
}
