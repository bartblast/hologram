"use strict";

import Interpreter from "./interpreter.mjs";

// TODO: write unit tests
export default class Console {
  static isDarkMode =
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches;

  static endGroup(groupName) {
    console.groupEnd(groupName);
  }

  static printData(data) {
    console.log(Interpreter.inspect(data));
  }

  static printDataItem(index, data) {
    console.log(
      `%c${index}: %c${Interpreter.inspect(data)}`,
      "color: purple; font-weight: bold",
      "color: black",
    );
  }

  static printHeader(header) {
    console.log(`%c${header}`, "color: blue");
  }

  static startGroup(groupName) {
    console.group(groupName);
  }
}
