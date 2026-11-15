"use strict";

import Hologram from "./hologram.mjs";

// The notice a tab shows once the server has stopped serving it: a small card in the corner of the
// page saying the page needs a reload, with a button that reloads it and one that puts the notice
// away. The framework never reloads on its own - that would throw away whatever the person was in
// the middle of - so it asks, and the person chooses when.
//
// The runtime's own element rather than the app's, appended to the body: a patch leaves alone the
// nodes it did not render, so it stays put across renders. Built from elements, text and style
// properties alone - no markup string and no style element - so a page under a strict content
// security policy or Trusted Types shows it with nothing to allow. The card starts from
// `all: initial`, so nothing the page's body passes down - a text transform, a letter spacing -
// reaches it, and what is inside starts from `all: revert`: the browser's own styles, the buttons'
// focus ring included, with no app rule for buttons or spans in between.

// How long after the card is up its text is written. A screen reader announces what changes in a
// status region, and a region whose text arrives in the same task as the region itself is one it
// passes over.
const ANNOUNCE_DELAY_MS = 100;

const ID = "hologram-reload-notice";

const TEXT =
  "This page was updated and needs a reload to keep your data in sync.";

export default class ReloadNotice {
  // Put away by the person, for the rest of the page's life: a notice that came back would only be
  // asking again.
  static #dismissed = false;

  // Made public to make tests easier
  static reset() {
    $.#dismissed = false;

    document.getElementById(ID)?.remove();
  }

  // Called after every render that finished, with whether the tab is stopped. Puts the notice up
  // when it should be up and is not - the first render after the stop, or a render after something
  // took it out of the document.
  static update(stopped) {
    if (!stopped || $.#dismissed || document.getElementById(ID) !== null) {
      return;
    }

    const text = document.createElement("span");

    Object.assign(text.style, {
      all: "revert",
      color: "inherit",
      font: "inherit",
    });

    document.body.appendChild($.#build(text));

    setTimeout(() => {
      text.textContent = TEXT;
    }, ANNOUNCE_DELAY_MS);
  }

  static #build(text) {
    const notice = document.createElement("div");
    notice.id = ID;
    notice.setAttribute("role", "status");

    Object.assign(notice.style, {
      all: "initial",
      alignItems: "center",
      background: "#1f2023",
      borderRadius: "8px",
      bottom: "16px",
      boxShadow: "0 4px 16px rgba(0, 0, 0, 0.25)",
      boxSizing: "border-box",
      color: "#f4f4f5",
      display: "flex",
      fontFamily:
        'system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
      fontSize: "14px",
      gap: "12px",
      lineHeight: "1.4",
      maxWidth: "min(420px, calc(100vw - 32px))",
      padding: "12px 12px 12px 16px",
      position: "fixed",
      right: "16px",
      textSizeAdjust: "100%",
      webkitTextSizeAdjust: "100%",
      zIndex: "2147483646",
    });

    const reload = $.#buildButton("Reload", {
      background: "#f4f4f5",
      color: "#1f2023",
      fontWeight: "600",
      padding: "6px 12px",
    });

    reload.addEventListener("click", () => Hologram.reloadBrowserLocation());

    const dismiss = $.#buildButton("×", {
      background: "transparent",
      color: "inherit",
      fontSize: "18px",
      lineHeight: "1",
      padding: "4px 6px",
    });

    dismiss.setAttribute("aria-label", "Dismiss");

    dismiss.addEventListener("click", () => {
      $.#dismissed = true;

      notice.remove();
    });

    notice.append(text, reload, dismiss);

    return notice;
  }

  static #buildButton(label, style) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;

    Object.assign(button.style, {
      all: "revert",
      border: "none",
      borderRadius: "6px",
      cursor: "pointer",
      flexShrink: "0",
      font: "inherit",
      ...style,
    });

    return button;
  }
}

const $ = ReloadNotice;
