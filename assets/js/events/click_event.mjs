"use strict";

import Type from "../type.mjs";

export default class ClickEvent {
  // TODO: add more event details
  static buildOperationParam(event) {
    return Type.map([
      [Type.atom("page_x"), Type.integer(event.pageX)],
      [Type.atom("page_y"), Type.integer(event.pageY)],
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
