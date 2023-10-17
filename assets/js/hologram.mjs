"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class Hologram {
  static clientsData = null;
  static isInitiated = false;
  static pageModule = null;
  static pageParams = null;

  // TODO: implement
  static init() {}

  // TODO: implement
  static mountPage() {
    window.__hologramPageReachableFunctionDefs__(Interpreter, Type);

    const mountData = window.__hologramPageMountData__(Type);
    Hologram.clientsData = mountData.clientsData;
    Hologram.pageModule = mountData.pageModule;
    Hologram.pageParams = mountData.pageParams;

    console.log("Hologram.clientsData =");
    console.debug(Hologram.clientsData);

    console.log("Hologram.pageModule =");
    console.debug(Hologram.pageModule);

    console.log("Hologram.pageParams =");
    console.debug(Hologram.pageParams);
  }

  static onReady(callback) {
    if (
      document.readyState === "interactive" ||
      document.readyState === "complete"
    ) {
      callback();
    } else {
      document.addEventListener("DOMContentLoaded", function listener() {
        document.removeEventListener("DOMContentLoaded", listener);
        callback();
      });
    }
  }

  static run() {
    Hologram.onReady(() => {
      if (!Hologram.isInitiated) {
        Hologram.init();
      }

      Hologram.mountPage();
    });
  }
}
