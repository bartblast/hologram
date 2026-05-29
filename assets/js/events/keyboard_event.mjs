"use strict";

import Type from "../type.mjs";

export default class KeyboardEvent {
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

  static isEventIgnored(_event) {
    return false;
  }
}
