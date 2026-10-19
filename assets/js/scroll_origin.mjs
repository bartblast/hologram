"use strict";

// Which physical sides a scroll container's content starts from. The browser reports scrollTop 0
// and scrollLeft 0 at the content start, so a container that starts its content at the bottom or
// the right (a column-reverse list, a right-to-left row) scrolls through negative positions, and
// its edges have to be measured from the side the origin sits on.
export default class ScrollOrigin {
  static #opposites = {
    bottom: "top",
    left: "right",
    right: "left",
    top: "bottom",
  };

  // Block start and inline start (for ltr) per writing mode.
  static #starts = {
    "horizontal-tb": ["top", "left"],
    "sideways-lr": ["left", "bottom"],
    "sideways-rl": ["right", "top"],
    "vertical-lr": ["left", "top"],
    "vertical-rl": ["right", "top"],
  };

  // The origin sides derived from a computed style: {horizontal: "left" | "right", vertical:
  // "top" | "bottom"}. Takes the style rather than the element so the rule can be tested as a
  // table. An unknown or missing writing mode resolves as horizontal-tb.
  static fromStyle(style) {
    const [blockStart, inlineStartLtr] =
      $.#starts[style.writingMode] ?? $.#starts["horizontal-tb"];

    const inlineStart =
      style.direction === "rtl" ? $.#opposites[inlineStartLtr] : inlineStartLtr;

    let starts = [blockStart, inlineStart];

    // A flex container lays its items along its own main axis, which -reverse flips, and stacks its
    // lines along the cross axis, which wrap-reverse flips. Both move where the content starts.
    if (style.display === "flex" || style.display === "inline-flex") {
      const column = style.flexDirection.startsWith("column");
      const mainStart = column ? blockStart : inlineStart;
      const crossStart = column ? inlineStart : blockStart;

      starts = [
        style.flexDirection.endsWith("-reverse")
          ? $.#opposites[mainStart]
          : mainStart,
        style.flexWrap === "wrap-reverse"
          ? $.#opposites[crossStart]
          : crossStart,
      ];
    }

    return {
      horizontal: starts.find((side) => side === "left" || side === "right"),
      vertical: starts.find((side) => side === "top" || side === "bottom"),
    };
  }

  // The origin sides of a scroll container, read from its computed style.
  static of(element) {
    return $.fromStyle(getComputedStyle(element));
  }
}

const $ = ScrollOrigin;
