"use strict";

import AssetPathRegistry from "./asset_path_registry.mjs";
import Bitstring from "./bitstring.mjs";
import Client from "./client.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Elixir_Code from "./elixir/code.mjs";
import Elixir_Hologram_Router_Helpers from "./elixir/hologram/router/helpers.mjs";
import Elixir_Kernel from "./elixir/kernel.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import MemoryStorage from "./memory_storage.mjs";
import Operation from "./operation.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

// Events
import ClickEvent from "./events/click_event.mjs";

import {attributesModule, eventListenersModule, init, toVNode} from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

// TODO: test
export default class Hologram {
  // Made public only to make commands easier to test
  static commandQueue = [];

  static #deps = {
    Bitstring: Bitstring,
    HologramBoxedError: HologramBoxedError,
    HologramInterpreterError: HologramInterpreterError,
    Interpreter: Interpreter,
    MemoryStorage: MemoryStorage,
    Type: Type,
    Utils: Utils,
  };

  static #isInitiated = false;
  static #mountData = null;
  static #pageModule = null;
  static #pageParams = null;
  static #virtualDocument = null;

  static handleEvent(event, eventType, operationSpecDom, defaultTarget) {
    const eventImpl = Hologram.#getEventImplementation(eventType);

    if (!eventImpl.isEventIgnored(event)) {
      event.preventDefault();

      const eventParam = eventImpl.buildOperationParam(event);

      const operation = Operation.fromSpecDom(
        operationSpecDom,
        defaultTarget,
        eventParam,
      );

      Operation.isAction(operation)
        ? Hologram.#executeAction(operation)
        : Hologram.commandQueue.push(operation);
    }
  }

  // Made public only to make it stubable in tests
  static render() {
    if (!Hologram.#virtualDocument) {
      Hologram.#virtualDocument = toVNode(window.document.documentElement);
    }

    const newVirtualDocument = Renderer.renderPage(
      Hologram.#pageModule,
      Hologram.#pageParams,
    );

    patch(Hologram.#virtualDocument, newVirtualDocument);

    Hologram.#virtualDocument = newVirtualDocument;
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

  // Deps: [:maps.get/2, :maps.put/3]
  static #executeAction(operation) {
    const name = Erlang_Maps["get/2"](Type.atom("name"), operation);
    const params = Erlang_Maps["get/2"](Type.atom("params"), operation);
    const target = Erlang_Maps["get/2"](Type.atom("target"), operation);

    const componentModule = ComponentRegistry.getComponentModule(target);
    const componentStruct = ComponentRegistry.getComponentStruct(target);
    const args = [name, params, componentStruct];

    const context = Interpreter.buildContext({
      module: componentModule,
      vars: {},
    });

    const resultComponentStruct = Interpreter.callNamedFunction(
      componentModule,
      "action",
      3,
      args,
      context,
    );

    let nextAction = Erlang_Maps["get/2"](
      Type.atom("next_action"),
      resultComponentStruct,
    );

    let nextCommand = Erlang_Maps["get/2"](
      Type.atom("next_command"),
      resultComponentStruct,
    );

    if (!Type.isNil(nextCommand)) {
      if (Type.isNil(Erlang_Maps["get/2"](Type.atom("target"), nextCommand))) {
        nextCommand = Erlang_Maps["put/3"](
          Type.atom("target"),
          target,
          nextCommand,
        );
      }

      Hologram.commandQueue.push(nextCommand);
    }

    let savedComponentStruct = Erlang_Maps["put/3"](
      Type.atom("next_action"),
      Type.nil(),
      resultComponentStruct,
    );

    savedComponentStruct = Erlang_Maps["put/3"](
      Type.atom("next_command"),
      Type.nil(),
      resultComponentStruct,
    );

    ComponentRegistry.putComponentStruct(target, savedComponentStruct);

    if (!Type.isNil(nextAction)) {
      if (Type.isNil(Erlang_Maps["get/2"](Type.atom("target"), nextAction))) {
        nextAction = Erlang_Maps["put/3"](
          Type.atom("target"),
          target,
          nextAction,
        );
      }

      Hologram.#executeAction(nextAction);
    } else {
      Hologram.render();
    }
  }

  static #getEventImplementation(eventType) {
    switch (eventType) {
      case "click":
        return ClickEvent;
    }
  }

  static #init() {
    Client.connect();

    Hologram.#defineManuallyPortedFunctions();

    window.console.inspect = (term) =>
      console.log("INSPECT: " + Interpreter.inspect(term));

    Hologram.#isInitiated = true;
  }

  static #loadMountData() {
    const mountData = window.__hologramPageMountData__(Hologram.#deps);

    Hologram.#mountData = mountData;
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

    ComponentRegistry.hydrate(Hologram.#mountData.componentRegistry);

    Hologram.#maybeInitAssetPathRegistry();

    Hologram.render();
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
}
