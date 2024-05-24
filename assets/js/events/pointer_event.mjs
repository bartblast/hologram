"use strict";

import MouseEvent from "../events/mouse_event.mjs";
import Type from "../type.mjs";

export default class PointerEvent {
  // TODO: add more fields specific to PointerEvent
  static buildOperationParam(event) {
    const mouseEventDetails = MouseEvent.buildOperationParam(event);

    const pointerEventDetails = Type.map([
      [
        Type.atom("pointer_type"),
        event.pointerType === "" ? Type.nil() : Type.atom(event.pointerType),
      ],
    ]);

    // PointerEvent inherits properties from MouseEvent
    // See: https://developer.mozilla.org/en-US/docs/Web/API/PointerEvent#instance_properties
    return Erlang_Maps["merge/2"](mouseEventDetails, pointerEventDetails);
  }

  static isEventIgnored(event) {
    return MouseEvent.isEventIgnored(event);
  }
}
