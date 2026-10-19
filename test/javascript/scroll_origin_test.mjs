"use strict";

import {assert, sinon} from "./support/helpers.mjs";

import ScrollOrigin from "../../assets/js/scroll_origin.mjs";

describe("ScrollOrigin", () => {
  describe("fromStyle()", () => {
    const assertOrigins = (cases) => {
      cases.forEach(([style, expected]) => {
        assert.deepStrictEqual(
          ScrollOrigin.fromStyle(style),
          expected,
          JSON.stringify(style),
        );
      });
    };

    const bottomLeft = {horizontal: "left", vertical: "bottom"};
    const bottomRight = {horizontal: "right", vertical: "bottom"};
    const topLeft = {horizontal: "left", vertical: "top"};
    const topRight = {horizontal: "right", vertical: "top"};

    it("combines flex reversal with direction and writing mode", () => {
      assertOrigins([
        [
          {
            direction: "rtl",
            display: "flex",
            flexDirection: "column-reverse",
          },
          bottomRight,
        ],
        [
          {direction: "rtl", display: "flex", flexDirection: "row-reverse"},
          topLeft,
        ],
        [
          {
            display: "flex",
            flexDirection: "column-reverse",
            writingMode: "vertical-rl",
          },
          topLeft,
        ],
        [
          {
            display: "flex",
            flexDirection: "row-reverse",
            writingMode: "vertical-rl",
          },
          bottomRight,
        ],
        [
          {
            display: "flex",
            flexDirection: "row",
            flexWrap: "wrap-reverse",
            writingMode: "vertical-rl",
          },
          topLeft,
        ],
      ]);
    });

    it("ignores flex properties on a non-flex container", () => {
      assertOrigins([
        [
          {
            display: "block",
            flexDirection: "column-reverse",
            flexWrap: "wrap-reverse",
          },
          topLeft,
        ],
        [{direction: "rtl", display: "grid"}, topRight],
      ]);
    });

    it("resolves a flex container's main and cross axes", () => {
      assertOrigins([
        [{display: "flex", flexDirection: "row"}, topLeft],
        [{display: "flex", flexDirection: "row-reverse"}, topRight],
        [{display: "flex", flexDirection: "column"}, topLeft],
        [{display: "flex", flexDirection: "column-reverse"}, bottomLeft],
        [
          {display: "flex", flexDirection: "row", flexWrap: "wrap-reverse"},
          bottomLeft,
        ],
        [
          {display: "flex", flexDirection: "column", flexWrap: "wrap-reverse"},
          topRight,
        ],
        [
          {
            display: "flex",
            flexDirection: "column-reverse",
            flexWrap: "wrap-reverse",
          },
          bottomRight,
        ],
        [{display: "inline-flex", flexDirection: "column-reverse"}, bottomLeft],
      ]);
    });

    it("resolves a writing mode and direction", () => {
      assertOrigins([
        [{}, topLeft],
        [{writingMode: "horizontal-tb"}, topLeft],
        [{direction: "rtl"}, topRight],
        [{writingMode: "vertical-rl"}, topRight],
        [{writingMode: "vertical-lr"}, topLeft],
        [{writingMode: "sideways-rl"}, topRight],
        [{writingMode: "sideways-lr"}, bottomLeft],
        [{direction: "rtl", writingMode: "vertical-rl"}, bottomRight],
        [{direction: "rtl", writingMode: "vertical-lr"}, bottomLeft],
        [{direction: "rtl", writingMode: "sideways-lr"}, topLeft],
        [{writingMode: "no-such-mode"}, topLeft],
      ]);
    });
  });

  describe("of()", () => {
    let originalGetComputedStyle;

    beforeEach(() => {
      originalGetComputedStyle = globalThis.getComputedStyle;
    });

    afterEach(() => {
      globalThis.getComputedStyle = originalGetComputedStyle;
    });

    it("reads the element's computed style", () => {
      const element = document.createElement("div");

      globalThis.getComputedStyle = sinon
        .stub()
        .returns({display: "flex", flexDirection: "column-reverse"});

      assert.deepStrictEqual(ScrollOrigin.of(element), {
        horizontal: "left",
        vertical: "bottom",
      });

      sinon.assert.calledOnceWithExactly(globalThis.getComputedStyle, element);
    });
  });
});
