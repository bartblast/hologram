"use strict";

// The error overlays the runtime puts over the page: a full-screen monospace
// surface showing a heading and the error below it.
//
// Content is either plain text, laid out as written, or lines of toned
// segments - a segment being a run of text and the tone it reads in, the shape
// Hologram.LiveReload.Diagnostic returns. The tones set what went wrong
// (`banner`) apart from the source it happened in (`body`), where it happened
// (`meta`) and the scaffolding holding those apart (`chrome`), so the lines
// worth reading aren't lost among the ones that only place them.
//
// Overlays are told apart by id, so each caller keeps its own and showing one
// doesn't disturb another. A dismissable overlay closes on its dismiss button
// or on Escape - a compilation error leaves the page meaningless and stays
// until a successful recompilation reloads it, whereas a runtime error often
// leaves the rest of the page usable, and an overlay with no way out would make
// the app impossible to exercise by hand.

const CLASS_PREFIX = "hologram-error-overlay";

const STYLE_ELEMENT_ID = "hologram-error-overlay-style";

// Written once into the page rather than onto every element, so the tones stay
// in one place and each line costs a class name instead of a style attribute.
//
// IMPORTANT!
// The tones are named by whoever classifies a report - by the server in
// Hologram.LiveReload.Diagnostic for a compiler diagnostic, and by
// uncaught_error_overlay.mjs for an uncaught error. A tone named there with no
// rule here renders unstyled. Always update them together.
//
// What was raised reads as plain white text. Where it came from reads in HOLO's
// lavender-gray below it, and within that, what was running in each frame is
// the part worth finding, so it is the part carrying weight - a frame from
// outside the app has none, since there is nothing in it to look for.
const STYLES = `
  .${CLASS_PREFIX} {
    background-color: #0f1014;
    box-sizing: border-box;
    color: #c2bbd3;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
    font-size: 14px;
    inset: 0;
    line-height: 1.6;
    overflow: auto;
    padding: 50px;
    position: fixed;
    z-index: 2147483647;
  }

  /* A frame is laid out as written and left to run its full length. Holding it
     to a reading measure would wrap whichever frames happened to overrun it,
     which reads as arbitrary among frames that are otherwise alike. Breaking
     inside a word is the last resort when the window is too narrow to fit one
     at all. */
  .${CLASS_PREFIX}__content {
    white-space: pre-wrap;
    word-wrap: break-word;
  }

  .${CLASS_PREFIX}__dismiss {
    background: none;
    border: none;
    color: inherit;
    cursor: pointer;
    font-size: 36px;
    line-height: 1;
    padding: 10px;
    position: absolute;
    right: 20px;
    top: 20px;
  }

  .${CLASS_PREFIX}__heading {
    color: #a78bfa;
    font-size: 36px;
    font-weight: 700;
    margin: 0 0 40px;
  }

  /* An empty line carries no text to give it height, and the output it came
     from uses blank lines to hold its parts apart. */
  .${CLASS_PREFIX}__line {
    min-height: 1.6em;
  }

  .${CLASS_PREFIX}__line--banner {
    margin-bottom: 20px;
  }

  .${CLASS_PREFIX}__tone-banner {
    color: #ffffff;
  }

  .${CLASS_PREFIX}__tone-body {
    font-weight: 700;
  }
`;

export default class ErrorOverlay {
  // The scrolling the page had before anything covered it. Overlays under
  // different ids can be up together, so it is taken when the first one goes up
  // and put back when the last one comes down - taking it per overlay would
  // save the "hidden" an earlier overlay had already set.
  static #pageOverflow = null;

  // The Escape handler to unbind when an overlay is taken away, null for one
  // that isn't dismissable. Keyed by overlay id, and holding an entry only
  // while that overlay is up.
  static #shown = new Map();

  static hide(id) {
    if (!$.#shown.has(id)) {
      return;
    }

    const handleKeydown = $.#shown.get(id);

    document.getElementById(id)?.remove();
    $.#shown.delete(id);

    if (handleKeydown !== null) {
      document.removeEventListener("keydown", handleKeydown);
    }

    if ($.#shown.size === 0) {
      document.body.style.overflow = $.#pageOverflow;
    }
  }

  static show({content, dismissable = false, heading, id}) {
    // Only the newest error is on screen under a given id. Whoever reported it
    // keeps the ones it replaces.
    $.hide(id);

    if ($.#shown.size === 0) {
      $.#pageOverflow = document.body.style.overflow;
    }

    document.body.style.overflow = "hidden";

    $.#ensureStyles();

    const overlay = document.createElement("div");
    overlay.className = CLASS_PREFIX;
    overlay.id = id;

    overlay.appendChild($.#buildHeading(heading));
    overlay.appendChild($.#buildContent(content));

    let handleKeydown = null;

    if (dismissable) {
      // Escape dismisses. Clicking through to the page behind doesn't, so a
      // stray click can't discard an error that's still being read.
      handleKeydown = (event) => {
        if (event.key === "Escape") {
          $.hide(id);
        }
      };

      // Prepended rather than appended so the error text stays the overlay's
      // last child. The button is positioned absolutely, so its place in the
      // document doesn't decide where it lands.
      overlay.prepend($.#buildDismissButton(id));

      document.addEventListener("keydown", handleKeydown);
    }

    document.body.appendChild(overlay);

    $.#shown.set(id, handleKeydown);
  }

  static #buildContent(content) {
    const element = document.createElement("div");
    element.className = `${CLASS_PREFIX}__content`;

    if (typeof content === "string") {
      element.textContent = content;

      return element;
    }

    content.forEach((segments) => element.appendChild($.#buildLine(segments)));

    return element;
  }

  static #buildDismissButton(id) {
    const button = document.createElement("button");
    button.className = `${CLASS_PREFIX}__dismiss`;
    button.textContent = "×";
    button.setAttribute("aria-label", "Dismiss");

    button.addEventListener("click", () => $.hide(id));

    return button;
  }

  static #buildHeading(heading) {
    const element = document.createElement("h1");
    element.className = `${CLASS_PREFIX}__heading`;
    element.textContent = heading;

    return element;
  }

  // A line reads in the tone of the segment it opens with, which is the whole
  // line unless a gutter or a frame's provenance comes first.
  static #buildLine(segments) {
    const element = document.createElement("div");

    element.className = `${CLASS_PREFIX}__line ${CLASS_PREFIX}__line--${segments[0].tone}`;

    segments.forEach(({text, tone}) => {
      const span = document.createElement("span");
      span.className = `${CLASS_PREFIX}__tone-${tone}`;
      span.textContent = text;

      element.appendChild(span);
    });

    return element;
  }

  static #ensureStyles() {
    if (document.getElementById(STYLE_ELEMENT_ID)) {
      return;
    }

    const style = document.createElement("style");
    style.id = STYLE_ELEMENT_ID;
    style.textContent = STYLES;

    document.head.appendChild(style);
  }
}

const $ = ErrorOverlay;
