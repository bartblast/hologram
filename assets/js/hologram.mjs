"use strict";

import AssetPathRegistry from "./asset_path_registry.mjs";
import Bitstring from "./bitstring.mjs";
import Elixir_Code from "./elixir/code.mjs";
import Elixir_Hologram_Router_Helpers from "./elixir/hologram/router/helpers.mjs";
import Elixir_Kernel from "./elixir/kernel.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import MemoryStorage from "./memory_storage.mjs";
import Renderer from "./renderer.mjs";
import Store from "./store.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

import {attributesModule, eventListenersModule, init, toVNode} from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

// TODO: test
export default class Hologram {
  static #deps = {
    Bitstring: Bitstring,
    HologramBoxedError: HologramBoxedError,
    HologramInterpreterError: HologramInterpreterError,
    Interpreter: Interpreter,
    MemoryStorage: MemoryStorage,
    Type: Type,
    Utils: Utils,
  };

  static #componentStructs = null;
  static #isInitiated = false;
  static #pageModule = null;
  static #pageParams = null;
  static #virtualDocument = null;

  static handleEvent(_event, _operationSpecVdom) {
    console.log("TODO");
  }

  static run() {
    Hologram.#onReady(() => {
      if (!Hologram.#isInitiated) {
        Hologram.#init();
      }

      try {
        Hologram.#mountPage();
      } catch (error) {
        if (error instanceof HologramBoxedError) {
          error.name = Interpreter.getErrorType(error);
          error.message = Interpreter.getErrorMessage(error);
        }

        throw error;
      }
    });
  }

  static #defineManuallyPortedFunctions() {
    window.Elixir_Code = {};
    window.Elixir_Code["ensure_compiled/1"] = Elixir_Code["ensure_compiled/1"];

    window.Elixir_Hologram_Router_Helpers = {};
    window.Elixir_Hologram_Router_Helpers["asset_path/1"] =
      Elixir_Hologram_Router_Helpers["asset_path/1"];

    window.Elixir_Kernel = {};
    window.Elixir_Kernel["inspect/1"] = Elixir_Kernel["inspect/1"];
    window.Elixir_Kernel["inspect/2"] = Elixir_Kernel["inspect/2"];
  }

  static #init() {
    Hologram.#defineManuallyPortedFunctions();

    window.console.inspect = (term) =>
      console.log("INSPECT: " + Interpreter.inspect(term));

    Hologram.#isInitiated = true;
  }

  static #loadMountData() {
    const mountData = window.__hologramPageMountData__(Hologram.#deps);

    Hologram.#componentStructs = mountData.componentStructs;
    Hologram.#pageModule = mountData.pageModule;
    Hologram.#pageParams = mountData.pageParams;
  }

  static #maybeInitAssetPathRegistry() {
    if (AssetPathRegistry.entries === null) {
      AssetPathRegistry.hydrate(window.__hologramAssetManifest__);
    }
  }

  static #mountPage() {
    window.__hologramPageReachableFunctionDefs__(Hologram.#deps);

    Hologram.#loadMountData();

    Store.hydrate(Hologram.#componentStructs);

    Hologram.#maybeInitAssetPathRegistry();

    Hologram.#render();
  }

  static #onReady(callback) {
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

  static #render() {
    if (!Hologram.#virtualDocument) {
      Hologram.#virtualDocument = toVNode(window.document.documentElement);
    }

    const newVirtualDocument = Renderer.renderPage(
      Hologram.#pageModule,
      Hologram.#pageParams,
    )[0];

    patch(Hologram.#virtualDocument, newVirtualDocument);

    Hologram.#virtualDocument = newVirtualDocument;
  }
}
