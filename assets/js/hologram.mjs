"use strict";

import AssetPathRegistry from "./asset_path_registry.mjs";
import Bitstring from "./bitstring.mjs";
import Client from "./client.mjs";
import CommandQueue from "./command_queue.mjs";
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
import MouseEvent from "./events/mouse_event.mjs";

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

  static #isInitiated = false;
  static #mountData = null;
  static #pageModule = null;
  static #pageParams = null;
  static #virtualDocument = null;

  // Made public to make tests easier
  // Deps: [:maps.get/2, :maps.put/3]
  static executeAction(action) {
    const name = Erlang_Maps["get/2"](Type.atom("name"), action);
    const params = Erlang_Maps["get/2"](Type.atom("params"), action);
    const target = Erlang_Maps["get/2"](Type.atom("target"), action);

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

      CommandQueue.push(nextCommand);
      CommandQueue.process();
    }

    let savedComponentStruct = Erlang_Maps["put/3"](
      Type.atom("next_action"),
      Type.nil(),
      resultComponentStruct,
    );

    savedComponentStruct = Erlang_Maps["put/3"](
      Type.atom("next_command"),
      Type.nil(),
      savedComponentStruct,
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

      Hologram.executeAction(nextAction);
    } else {
      Hologram.render();
    }
  }

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

      if (Operation.isAction(operation)) {
        if (Hologram.#isPrefetchPageAction(operation)) {
          Hologram.prefetchPage(operation, event.target);
        } else {
          Hologram.executeAction(operation);
        }
      } else {
        CommandQueue.push(operation);
        CommandQueue.process();
      }
    }
  }

  // Made public to make tests easier
  static prefetchPage(operation, target) {
    // TODO: implement
  }

  // Made public to make tests easier
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

  static #getEventImplementation(eventType) {
    switch (eventType) {
      case "click":
        // TODO: change to PointerEvent when Firefox and Safari bugs are fixed:
        // See: https://stackoverflow.com/a/76900433
        // See: https://bugzilla.mozilla.org/show_bug.cgi?id=1675847
        // See: https://bugs.webkit.org/show_bug.cgi?id=218665
        return MouseEvent;
    }
  }

  static #init() {
    Client.connect();

    Hologram.#defineManuallyPortedFunctions();

    window.console.inspect = (term) =>
      console.log("INSPECT: " + Interpreter.inspect(term));

    Hologram.#isInitiated = true;
  }

  // Deps: [:maps.get/2]
  static #isPrefetchPageAction(operation) {
    const prefetchPageActionName =
      Elixir_Hologram_RuntimeSettings["prefetch_page_action_name/0"]();

    const actionName = Erlang_Maps["get/2"](Type.atom("name"), operation);

    return Interpreter.isEqual(actionName, prefetchPageActionName);
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
