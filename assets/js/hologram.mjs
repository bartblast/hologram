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

    console.log("window.__hologramPageMountData__ =");
    console.dir(window.__hologramPageMountData__);

    const mountData = window.__hologramPageMountData__(Type);

    console.log("mountData =");
    console.dir(mountData);

    Hologram.clientsData = mountData.clientsData;
    Hologram.pageModule = mountData.pageModule;
    Hologram.pageParams = mountData.pageParams;

    console.log("Hologram.clientsData =");
    console.dir(Hologram.clientsData);

    console.log("Hologram.pageModule =");
    console.dir(Hologram.pageModule);

    console.log("Hologram.pageParams =");
    console.dir(Hologram.pageParams);
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
