"use strict";

import Type from "../type.mjs";

export default class MouseEvent {
  // Allow the browser's native default. Preventing it suppresses native behaviour such as text
  // selection, so the default is left to run; a binding that needs to suppress it opts in with
  // prevent_default.
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    return Type.map([
      [Type.atom("client_x"), Type.float(event.clientX)],
      [Type.atom("client_y"), Type.float(event.clientY)],
      [Type.atom("movement_x"), Type.float(event.movementX)],
      [Type.atom("movement_y"), Type.float(event.movementY)],
      [Type.atom("offset_x"), Type.float(event.offsetX)],
      [Type.atom("offset_y"), Type.float(event.offsetY)],
      [Type.atom("page_x"), Type.float(event.pageX)],
      [Type.atom("page_y"), Type.float(event.pageY)],
      [Type.atom("screen_x"), Type.float(event.screenX)],
      [Type.atom("screen_y"), Type.float(event.screenY)],
    ]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
