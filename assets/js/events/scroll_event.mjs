"use strict";

import Type from "../type.mjs";

export default class ScrollEvent {
  // The DOM scroll event is not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    const target = event.target;

    // A window or document scroll fires on the document, whose scroll offsets live on the scrolling
    // element (the viewport scroller), not on the document itself. An element scroll fires on the
    // element, which carries its own offsets.
    const scroller = target === document ? document.scrollingElement : target;

    return Type.map([
      [Type.atom("scroll_left"), Type.float(scroller.scrollLeft)],
      [Type.atom("scroll_top"), Type.float(scroller.scrollTop)],
    ]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
