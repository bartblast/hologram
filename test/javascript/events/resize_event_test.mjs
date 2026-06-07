"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ResizeEvent from "../../../assets/js/events/resize_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ResizeEvent", () => {
  describe("buildOperationParam()", () => {
    it("builds an element payload from the observer entry's box sizes", () => {
      const event = {
        borderBoxSize: [{blockSize: 200, inlineSize: 300}],
        contentBoxSize: [{blockSize: 190, inlineSize: 290}],
        devicePixelContentBoxSize: [{blockSize: 380, inlineSize: 580}],
      };

      const result = ResizeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.atom("border_box_size"),
            Type.map([
              [Type.atom("block_size"), Type.float(200)],
              [Type.atom("inline_size"), Type.float(300)],
            ]),
          ],
          [
            Type.atom("content_box_size"),
            Type.map([
              [Type.atom("block_size"), Type.float(190)],
              [Type.atom("inline_size"), Type.float(290)],
            ]),
          ],
          [
            Type.atom("device_pixel_content_box_size"),
            Type.map([
              [Type.atom("block_size"), Type.float(380)],
              [Type.atom("inline_size"), Type.float(580)],
            ]),
          ],
        ]),
      );
    });

    it("uses nil for device_pixel_content_box_size when the browser lacks it", () => {
      const event = {
        borderBoxSize: [{blockSize: 200, inlineSize: 300}],
        contentBoxSize: [{blockSize: 190, inlineSize: 290}],
      };

      const result = ResizeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.atom("border_box_size"),
            Type.map([
              [Type.atom("block_size"), Type.float(200)],
              [Type.atom("inline_size"), Type.float(300)],
            ]),
          ],
          [
            Type.atom("content_box_size"),
            Type.map([
              [Type.atom("block_size"), Type.float(190)],
              [Type.atom("inline_size"), Type.float(290)],
            ]),
          ],
          [Type.atom("device_pixel_content_box_size"), Type.nil()],
        ]),
      );
    });

    it("builds a window payload from the window's size properties", () => {
      const event = {
        target: {
          devicePixelRatio: 2,
          document: {documentElement: {clientHeight: 760, clientWidth: 1009}},
          innerHeight: 768,
          innerWidth: 1024,
          outerHeight: 900,
          outerWidth: 1280,
        },
      };

      const result = ResizeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("client_height"), Type.float(760)],
          [Type.atom("client_width"), Type.float(1009)],
          [Type.atom("device_pixel_ratio"), Type.float(2)],
          [Type.atom("inner_height"), Type.float(768)],
          [Type.atom("inner_width"), Type.float(1024)],
          [Type.atom("outer_height"), Type.float(900)],
          [Type.atom("outer_width"), Type.float(1280)],
        ]),
      );
    });
  });

  it("isEventIgnored()", () => {
    assert.isFalse(ResizeEvent.isEventIgnored({}));
  });
});
