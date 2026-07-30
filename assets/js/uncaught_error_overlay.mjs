"use strict";

const OVERLAY_ID = "hologram-uncaught-error-overlay";

// Renders an uncaught client error in the page, in the visual language of the
// live reload compilation error overlay. Unlike that one it can be dismissed:
// a compilation error leaves the page meaningless, whereas a runtime error
// often leaves the rest of it usable, and an overlay with no way out would
// make the app impossible to exercise by hand after an incidental error.
export default class UncaughtErrorOverlay {
  // The page's own overflow, restored on dismissal so the overlay doesn't leave
  // the document permanently unscrollable.
  static #pageOverflow = null;

  static hide() {
    const overlay = document.getElementById(OVERLAY_ID);

    if (overlay === null) {
      return;
    }

    overlay.remove();
    document.removeEventListener("keydown", $.#handleKeydown);

    document.body.style.overflow = $.#pageOverflow;
    $.#pageOverflow = null;
  }

  static show(content) {
    // Only the newest error is on screen at a time. The console keeps the ones
    // it replaces.
    $.hide();

    $.#pageOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const overlay = document.createElement("div");
    overlay.id = OVERLAY_ID;

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

    const heading = document.createElement("h1");
    heading.textContent = "Runtime Error";

    heading.style.cssText = `
      margin-top: 0;
      margin-bottom: 50px;
      font-size: 36px;
      font-weight: 700;
      color: #A78BFA;
    `;

    const dismissButton = document.createElement("button");
    dismissButton.textContent = "×";
    dismissButton.setAttribute("aria-label", "Dismiss");

    dismissButton.style.cssText = `
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

    dismissButton.addEventListener("click", () => $.hide());

    const contentContainer = document.createElement("div");
    contentContainer.textContent = content;

    overlay.appendChild(dismissButton);
    overlay.appendChild(heading);
    overlay.appendChild(contentContainer);

    document.body.appendChild(overlay);

    document.addEventListener("keydown", $.#handleKeydown);
  }

  // Escape dismisses. Clicking through to the page behind doesn't, so a stray
  // click can't discard an error that's still being read.
  static #handleKeydown(event) {
    if (event.key === "Escape") {
      $.hide();
    }
  }
}

const $ = UncaughtErrorOverlay;
