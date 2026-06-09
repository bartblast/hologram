"use strict";

import Type from "../type.mjs";

export default class ResizeEvent {
  // The DOM resize event is not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    // The payload carries only the data the event itself provides. An element resize arrives as a
    // ResizeObserverEntry (identified by borderBoxSize), which snapshots the element's box sizes at
    // resize time, so those are forwarded. A window resize arrives as the DOM resize event, which
    // carries no size data of its own - the window's size properties are live globals, not event
    // data (and some, like outerWidth, may not even be updated yet when the event fires) - so its
    // payload is empty.
    if (event.borderBoxSize) {
      // A box property is an array (one entry per CSS fragment); observed elements are
      // single-fragment, so the first entry is taken. devicePixelContentBoxSize is absent on
      // browsers that do not support it, in which case its value is nil. It is part of the Resize
      // Observer spec, but no Safari version implements it - WebKit computes device-pixel sizes
      // only after the paint cycle, while resize observations are delivered before it.
      // TODO: once Safari ships devicePixelContentBoxSize
      // (https://bugs.webkit.org/show_bug.cgi?id=219005) and unsupported versions phase out,
      // remove the nil fallback and update the docs that explain the Safari gap (the website
      // Events page, llms-full.txt, usage-rules.md).
      const devicePixel = event.devicePixelContentBoxSize;

      return Type.map([
        [Type.atom("border_box_size"), $.#sizeMap(event.borderBoxSize[0])],
        [Type.atom("content_box_size"), $.#sizeMap(event.contentBoxSize[0])],
        [
          Type.atom("device_pixel_content_box_size"),
          devicePixel ? $.#sizeMap(devicePixel[0]) : Type.nil(),
        ],
      ]);
    }

    return Type.map();
  }

  static isEventIgnored(_event) {
    return false;
  }

  // Maps a ResizeObserverSize ({inlineSize, blockSize}) to a boxed %{block_size, inline_size} map.
  static #sizeMap(size) {
    return Type.map([
      [Type.atom("block_size"), Type.float(size.blockSize)],
      [Type.atom("inline_size"), Type.float(size.inlineSize)],
    ]);
  }
}

const $ = ResizeEvent;
