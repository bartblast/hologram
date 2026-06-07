"use strict";

import Type from "../type.mjs";

export default class ResizeEvent {
  // The DOM resize event is not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    // An element resize arrives as a ResizeObserverEntry (identified by borderBoxSize) and reports
    // the entry's box sizes. A window resize arrives as the DOM resize event (its target is the
    // window) and reports the window's size properties. Each mirrors its own native API.
    if (event.borderBoxSize) {
      // A box property is an array (one entry per CSS fragment); observed elements are
      // single-fragment, so the first entry is taken. devicePixelContentBoxSize is absent on
      // browsers that do not support it, in which case its key is nil.
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

    const win = event.target;
    const docEl = win.document.documentElement;

    return Type.map([
      [Type.atom("client_height"), Type.float(docEl.clientHeight)],
      [Type.atom("client_width"), Type.float(docEl.clientWidth)],
      [Type.atom("device_pixel_ratio"), Type.float(win.devicePixelRatio)],
      [Type.atom("inner_height"), Type.float(win.innerHeight)],
      [Type.atom("inner_width"), Type.float(win.innerWidth)],
      [Type.atom("outer_height"), Type.float(win.outerHeight)],
      [Type.atom("outer_width"), Type.float(win.outerWidth)],
    ]);
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
