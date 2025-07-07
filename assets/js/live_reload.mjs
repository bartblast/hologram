"use strict";

export default class LiveReload {
  static showErrorOverlay(content) {
    const existingOverlay = document.getElementById(
      "hologram-live-reload-error-overlay",
    );

    if (existingOverlay) {
      existingOverlay.remove();
    }

    // Disable body scrolling
    document.body.style.overflow = "hidden";

    const overlay = document.createElement("div");
    overlay.id = "hologram-live-reload-error-overlay";

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

    // Create and style the h1 heading
    const heading = document.createElement("h1");
    heading.textContent = "Compilation Error";
    heading.style.cssText = `
      margin-top: 0;
      margin-bottom: 50px;
      font-size: 36px;
      font-weight: 700;
      color: #A78BFA;
    `;

    // Create content container
    const contentContainer = document.createElement("div");
    contentContainer.textContent = content;

    overlay.appendChild(heading);
    overlay.appendChild(contentContainer);

    document.body.appendChild(overlay);
  }
}
