"use strict";

import Type from "../type.mjs";

export default class MouseMoveEvent {
  static buildOperationParam(event) {
    return Type.map([
      [Type.atom("page_x"), Type.float(event.pageX)],
      [Type.atom("page_y"), Type.float(event.pageY)],
    ]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
