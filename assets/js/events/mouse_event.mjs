"use strict";

import Type from "../type.mjs";

export default class MouseEvent {
  // TODO: add more fields specific to MouseEvent
  static buildOperationParam(event) {
    return Type.map([
      [Type.atom("page_x"), Type.float(event.pageX)],
      [Type.atom("page_y"), Type.float(event.pageY)],
    ]);
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
