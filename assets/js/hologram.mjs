"use strict";

import Bitstring from "./bitstring.mjs";
import Elixir_Kernel from "./elixir/kernel.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import MemoryStorage from "./memory_storage.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";

export default class Hologram {
  static deps = {
    Bitstring: Bitstring,
    HologramBoxedError: HologramBoxedError,
    HologramInterpreterError: HologramInterpreterError,
    Interpreter: Interpreter,
    MemoryStorage: MemoryStorage,
    Type: Type,
  };

  static clientsData = null;
  static isInitiated = false;
  static pageModule = null;
  static pageParams = null;

  static init() {
    window.Elixir_Kernel = Elixir_Kernel;

    window.console.inspect = (term) => Interpreter.inspect(term);
  }

  static mountPage() {
    window.__hologramPageReachableFunctionDefs__(Hologram.deps);

    const mountData = window.__hologramPageMountData__(Hologram.deps);
    Hologram.clientsData = mountData.clientsData;
    Hologram.pageModule = mountData.pageModule;
    Hologram.pageParams = mountData.pageParams;

    Renderer.renderPage(
      mountData.pageModule,
      mountData.pageParam,
      mountData.clientsData,
    );
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

      try {
        Hologram.mountPage();
      } catch (error) {
        if (error instanceof HologramBoxedError) {
          error.name = Interpreter.fetchErrorType(error);
          error.message = Interpreter.fetchErrorMessage(error);
        }

        throw error;
      }
    });
  }
}
