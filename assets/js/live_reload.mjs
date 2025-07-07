"use strict";

export default class LiveReload {
  static showErrorOverlay(content) {
    const existingOverlay = document.getElementById(
      "hologram-live-reload-error-overlay",
    );

    if (existingOverlay) {
      existingOverlay.remove();
    }

    const overlay = document.createElement("div");
    overlay.id = "hologram-live-reload-error-overlay";

    overlay.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      background-color: black;
      color: white;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
      font-size: 14px;
      z-index: 2147483647;
      padding: 20px;
      box-sizing: border-box;
      overflow: auto;
      white-space: pre-wrap;
      word-wrap: break-word;
    `;

    overlay.textContent = content;

    document.body.appendChild(overlay);
  }
}
