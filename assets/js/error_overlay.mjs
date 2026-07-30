"use strict";

// The error overlays the runtime puts over the page: a full-screen monospace
// surface showing a heading and the error text laid out as written.
//
// Overlays are told apart by id, so each caller keeps its own and showing one
// doesn't disturb another. A dismissable overlay closes on its dismiss button
// or on Escape - a compilation error leaves the page meaningless and stays
// until a successful recompilation reloads it, whereas a runtime error often
// leaves the rest of the page usable, and an overlay with no way out would make
// the app impossible to exercise by hand.
export default class ErrorOverlay {
  // What taking an overlay away needs to know: the scrolling the page had
  // before it was covered, and the Escape handler to unbind. Keyed by overlay
  // id, and holding an entry only while that overlay is up.
  static #shown = new Map();

  static hide(id) {
    const entry = $.#shown.get(id);

    if (entry === undefined) {
      return;
    }

    document.getElementById(id)?.remove();
    $.#shown.delete(id);

    if (entry.handleKeydown !== null) {
      document.removeEventListener("keydown", entry.handleKeydown);
    }

    document.body.style.overflow = entry.pageOverflow;
  }

  static show({content, dismissable = false, heading, id}) {
    // Only the newest error is on screen under a given id. Whoever reported it
    // keeps the ones it replaces.
    $.hide(id);

    const pageOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const overlay = document.createElement("div");
    overlay.id = id;

    overlay.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      background-color: #0F1014;
      color: #C2BBD3;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
      font-size: 14px;
      z-index: 2147483647;
      padding: 50px;
      box-sizing: border-box;
      overflow: auto;
      white-space: pre-wrap;
      word-wrap: break-word;
    `;

    const headingElement = document.createElement("h1");
    headingElement.textContent = heading;

    headingElement.style.cssText = `
      margin-top: 0;
      margin-bottom: 50px;
      font-size: 36px;
      font-weight: 700;
      color: #A78BFA;
    `;

    const contentContainer = document.createElement("div");
    contentContainer.textContent = content;

    overlay.appendChild(headingElement);
    overlay.appendChild(contentContainer);

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

    $.#shown.set(id, {handleKeydown, pageOverflow});
  }

  static #buildDismissButton(id) {
    const button = document.createElement("button");
    button.textContent = "×";
    button.setAttribute("aria-label", "Dismiss");

    button.style.cssText = `
      position: absolute;
      top: 20px;
      right: 20px;
      background: none;
      border: none;
      color: #C2BBD3;
      font-size: 36px;
      line-height: 1;
      cursor: pointer;
      padding: 10px;
    `;

    button.addEventListener("click", () => $.hide(id));

    return button;
  }
}

const $ = ErrorOverlay;
