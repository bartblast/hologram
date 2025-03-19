"use strict";

export default class Logger {
  static key = "hologram_logs";

  static debug(message) {
    $.#log("debug", message);
  }

  static getLogs() {
    return sessionStorage.getItem($.key);
  }

  static #log(level, message) {
    sessionStorage.setItem(
      $.key,
      `${$.getLogs() || ""}[${level}] ${message}\n`,
    );
  }
}

const $ = Logger;
