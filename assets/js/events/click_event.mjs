"use strict";

import Type from "../type.mjs";

export default class ClickEvent {
  // TODO: add event details
  static buildOperationParam(_event) {
    return Type.map([]);
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
