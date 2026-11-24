"use strict";

export default class Logger {
  static key = "hologram_logs";

  static debug(message) {
    $.#log("debug", message);
  }

  static getLogs() {
    return sessionStorage.getItem($.key);
  }

  // Best-effort. Session storage has a quota the log itself can fill, it survives reloads, and a
  // browser can refuse access to it outright. Logging sits in front of code that has to run, like
  // a reconnect or a reset, so a line that can't be written is dropped and nothing else changes.
  static #log(level, message) {
    try {
      sessionStorage.setItem(
        $.key,
        `${$.getLogs() || ""}[${level}] ${message}\n`,
      );
      // eslint-disable-next-line no-empty
    } catch {}
  }
}

const $ = Logger;
