"use strict";

import AssetPathRegistry from "./asset_path_registry.mjs";
import Bitstring from "./bitstring.mjs";
import Client from "./client.mjs";
import CommandQueue from "./command_queue.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import MemoryStorage from "./memory_storage.mjs";
import Operation from "./operation.mjs";
import PersistentStorage from "./persistent_storage.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";
import Vdom from "./vdom.mjs";

// Events
import ChangeEvent from "./events/change_event.mjs";
import FocusEvent from "./events/focus_event.mjs";
import MouseEvent from "./events/mouse_event.mjs";
import PointerEvent from "./events/pointer_event.mjs";
import SubmitEvent from "./events/submit_event.mjs";
import TransitionEvent from "./events/transition_event.mjs";

import ManuallyPortedElixirCldrLocale from "./elixir/cldr/locale.mjs";
import ManuallyPortedElixirCldrValidityU from "./elixir/cldr/validity/u.mjs";
import ManuallyPortedElixirCode from "./elixir/code.mjs";
import ManuallyPortedElixirHologramRouterHelpers from "./elixir/hologram/router/helpers.mjs";
import ManuallyPortedElixirIO from "./elixir/io.mjs";
import ManuallyPortedElixirKernel from "./elixir/kernel.mjs";
import ManuallyPortedElixirString from "./elixir/string.mjs";

import {attributesModule, eventListenersModule, init, toVNode} from "snabbdom";

const patch = init([attributesModule, eventListenersModule]);

// TODO: test
export default class Hologram {
  // Made public to make tests easier
  static prefetchedPages = new Map();

  // Made public to make tests easier
  static virtualDocument = null;

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

  // Made public to make tests easier
  // Deps: [:maps.get/2, :maps.put/3]
  static executeAction(action) {
    const startTime = performance.now();
    globalThis.hologram.isProfilingEnabled = true;

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
      Type.atom("action"),
      Type.list(args),
      context,
    );

    let nextAction = Erlang_Maps["get/2"](
      Type.atom("next_action"),
      resultComponentStruct,
    );

    const nextPage = Erlang_Maps["get/2"](
      Type.atom("next_page"),
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

      Hologram.executeAsyncCommand(nextCommand);
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

    globalThis.hologram.isProfilingEnabled = false;

    console.log(
      "Hologram: action",
      `:${name.value}`,
      "executed in",
      Math.round(performance.now() - startTime),
      "ms",
    );

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
      Hologram.#replaceHistoryState();
    }

    if (!Type.isNil(nextPage)) {
      Hologram.navigateToPage(nextPage);
    }
  }

  static executeAsyncCommand(command) {
    return Utils.runAsyncTask(() => {
      CommandQueue.push(command);
      CommandQueue.process();
    });
  }

  // Made public to make tests easier
  static executeLoadPrefetchedPageAction(action, eventTargetNode) {
    Hologram.#ensureDomNodeHasHologramId(eventTargetNode);

    const toParam = Hologram.#getToParam(action);
    const pagePath = Hologram.#buildPagePath(toParam);

    const mapKey = Hologram.#buildPrefetchedPagesMapKey(
      eventTargetNode,
      pagePath,
    );

    const mapValue = Hologram.prefetchedPages.get(mapKey);

    if (typeof mapValue === "undefined") {
      return;
    }

    if (mapValue.html === null) {
      mapValue.isNavigateConfirmed = true;
    } else {
      Hologram.prefetchedPages.delete(mapKey);
      Hologram.loadPage(pagePath, mapValue.html);
    }
  }

  // Made public to make tests easier
  static executePrefetchPageAction(action, eventTargetNode) {
    Hologram.#ensureDomNodeHasHologramId(eventTargetNode);

    const toParam = Hologram.#getToParam(action);
    const pagePath = Hologram.#buildPagePath(toParam);

    const mapKey = Hologram.#buildPrefetchedPagesMapKey(
      eventTargetNode,
      pagePath,
    );

    if (
      !Hologram.prefetchedPages.has(mapKey) ||
      Hologram.#isPrefetchPageTimedOut(mapKey)
    ) {
      Hologram.prefetchedPages.set(mapKey, {
        html: null,
        isNavigateConfirmed: false,
        pagePath: pagePath,
        timestamp: Date.now(),
      });

      Client.fetchPage(
        toParam,
        (resp) => Hologram.handlePrefetchPageSuccess(mapKey, resp),
        (resp) => Hologram.handlePrefetchPageError(mapKey, resp),
      );
    }
  }

  static handlePrefetchPageError(mapKey, _resp) {
    const mapValue = Hologram.prefetchedPages.get(mapKey);

    if (typeof mapValue === "undefined") {
      return;
    }

    throw new HologramRuntimeError(
      `page prefetch failed: ${mapValue.pagePath}`,
    );
  }

  static handlePrefetchPageSuccess(mapKey, html) {
    const mapValue = Hologram.prefetchedPages.get(mapKey);

    if (typeof mapValue === "undefined") {
      return;
    }

    if (mapValue.isNavigateConfirmed) {
      Hologram.prefetchedPages.delete(mapKey);
      Hologram.loadPage(mapValue.pagePath, html);
    } else {
      mapValue.html = html;
    }
  }

  static handleUiEvent(event, eventType, operationSpecDom, defaultTarget) {
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
        switch (Hologram.#getActionName(operation)) {
          case "__load_prefetched_page__":
            return Hologram.executeLoadPrefetchedPageAction(
              operation,
              event.target,
            );

          case "__prefetch_page__":
            return Hologram.executePrefetchPageAction(operation, event.target);

          default:
            return Hologram.executeAction(operation);
        }
      } else {
        Hologram.executeAsyncCommand(operation);
      }
    }
  }

  // Made public to make tests easier
  static loadPage(pagePath, html) {
    window.requestAnimationFrame(() => {
      Hologram.#patchPage(html);
      window.scrollTo(0, 0);
      history.pushState(null, null, pagePath);
    });
  }

  // Made public to make tests easier
  static navigateToPage(toParam) {
    const pagePath = Hologram.#buildPagePath(toParam);

    Client.fetchPage(
      toParam,
      (resp) => Hologram.loadPage(pagePath, resp),
      (_resp) => {
        throw new HologramRuntimeError(
          "Failed to navigate to page: " + pagePath,
        );
      },
    );
  }

  // Made public to make tests easier
  static render() {
    const startTime = performance.now();

    const newVirtualDocument = Renderer.renderPage(
      Hologram.#pageModule,
      Hologram.#pageParams,
    );

    Hologram.virtualDocument = patch(
      Hologram.virtualDocument,
      newVirtualDocument,
    );

    console.log(
      "Hologram: page rendered in",
      Math.round(performance.now() - startTime),
      "ms",
    );
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

  static #buildPagePath(toParam) {
    return Bitstring.toText(
      Elixir_Hologram_Router_Helpers["page_path/1"](toParam),
    );
  }

  static #buildPrefetchedPagesMapKey(eventTargetNode, pagePath) {
    return `${eventTargetNode.__hologramId__}:${pagePath}`;
  }

  static #defineManuallyPortedFunctions() {
    Interpreter.defineManuallyPortedFunction(
      "Cldr.Locale",
      "language_data/0",
      "public",
      ManuallyPortedElixirCldrLocale["language_data/0"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Cldr.Validity.U",
      "encode_key/2",
      "public",
      ManuallyPortedElixirCldrValidityU["encode_key/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Code",
      "ensure_compiled/1",
      "public",
      ManuallyPortedElixirCode["ensure_compiled/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Router.Helpers",
      "asset_path/1",
      "public",
      ManuallyPortedElixirHologramRouterHelpers["asset_path/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "IO",
      "inspect/1",
      "public",
      ManuallyPortedElixirIO["inspect/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "IO",
      "inspect/2",
      "public",
      ManuallyPortedElixirIO["inspect/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "IO",
      "inspect/3",
      "public",
      ManuallyPortedElixirIO["inspect/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Kernel",
      "inspect/1",
      "public",
      ManuallyPortedElixirKernel["inspect/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Kernel",
      "inspect/2",
      "public",
      ManuallyPortedElixirKernel["inspect/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "String",
      "downcase/1",
      "public",
      ManuallyPortedElixirString["downcase/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "String",
      "downcase/2",
      "public",
      ManuallyPortedElixirString["downcase/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "String",
      "replace/3",
      "public",
      ManuallyPortedElixirString["replace/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "String",
      "upcase/1",
      "public",
      ManuallyPortedElixirString["upcase/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "String",
      "upcase/2",
      "public",
      ManuallyPortedElixirString["upcase/2"],
    );
  }

  static #ensureDomNodeHasHologramId(eventNode) {
    if (typeof eventNode.__hologramId__ === "undefined") {
      eventNode.__hologramId__ = crypto.randomUUID();
    }
  }

  // Deps: [:maps.get/2]
  static #getActionName(action) {
    return Erlang_Maps["get/2"](Type.atom("name"), action).value;
  }

  static #getEventImplementation(eventType) {
    switch (eventType) {
      case "blur":
      case "focus":
        return FocusEvent;

      case "change":
        return ChangeEvent;

      case "click":
        // TODO: change to PointerEvent when Firefox and Safari bugs are fixed:
        // See: https://stackoverflow.com/a/76900433
        // See: https://bugzilla.mozilla.org/show_bug.cgi?id=1675847
        // See: https://bugs.webkit.org/show_bug.cgi?id=218665
        return MouseEvent;

      case "pointerdown":
      case "pointerup":
        return PointerEvent;

      case "submit":
        return SubmitEvent;

      case "transitioncancel":
      case "transitionend":
      case "transitionrun":
      case "transitionstart":
        return TransitionEvent;
    }
  }

  // Deps: [:maps.get/2]
  static #getToParam(operation) {
    return Erlang_Maps["get/2"](
      Type.atom("to"),
      Erlang_Maps["get/2"](Type.atom("params"), operation),
    );
  }

  static async #handlePopstateEvent(event) {
    const pageSnapshot = await PersistentStorage.getPageSnapshot(event.state);

    const {componentRegistryEntries, pageModule, pageParams} =
      pageSnapshot.data;

    ComponentRegistry.hydrate(componentRegistryEntries);
    Hologram.#pageModule = pageModule;
    Hologram.#pageParams = pageParams;

    Hologram.render();
  }

  // Executed only once, on the initial page load.
  static #init() {
    window.addEventListener("error", (event) => {
      if (event.error instanceof HologramBoxedError) {
        console.error(`${event.error.message}\n`, event.error);
        event.preventDefault();
      }
    });

    PersistentStorage.init("dev");

    Client.connect();

    Hologram.#defineManuallyPortedFunctions();

    window.addEventListener("popstate", Hologram.#handlePopstateEvent);

    window.addEventListener("pageshow", (event) => {
      if (event.persisted) {
        PersistentStorage.init("dev");
        Client.connect();
      }
    });

    Hologram.virtualDocument = toVNode(document.documentElement);
    Vdom.addKeysToLinkAndScriptVnodes(Hologram.virtualDocument);

    console.inspect = (term) => console.log(Interpreter.inspect(term));

    Hologram.#isInitiated = true;
  }

  static #isPrefetchPageTimedOut(mapKey) {
    return (
      Date.now() - Hologram.prefetchedPages.get(mapKey).timestamp >
      Config.fetchPageTimeoutMs
    );
  }

  static #loadMountData() {
    const mountData = globalThis.hologram.pageMountData(Hologram.#deps);

    Hologram.#mountData = mountData;
    Hologram.#pageModule = mountData.pageModule;
    Hologram.#pageParams = mountData.pageParams;
  }

  static #maybeInitAssetPathRegistry() {
    if (AssetPathRegistry.entries === null) {
      AssetPathRegistry.hydrate(globalThis.hologram.assetManifest);
    }
  }

  static #mountPage() {
    globalThis.hologram.pageReachableFunctionDefs(Hologram.#deps);

    Hologram.#loadMountData();

    ComponentRegistry.hydrate(Hologram.#mountData.componentRegistry);

    Hologram.#maybeInitAssetPathRegistry();

    Hologram.prefetchedPages.clear();

    Hologram.render();

    Hologram.#replaceHistoryState();
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

  // TODO: raise error if there is no head or body
  static #patchPage(html) {
    globalThis.hologram.pageScriptLoaded = false;

    const newVirtualDocument = Vdom.from(html);

    Hologram.virtualDocument.data = newVirtualDocument.data;

    const oldBody = Hologram.virtualDocument.children.find(
      (child) => child.sel === "body",
    );

    const newBody = newVirtualDocument.children.find(
      (child) => child.sel === "body",
    );

    const oldHead = Hologram.virtualDocument.children.find(
      (child) => child.sel === "head",
    );

    const newHead = newVirtualDocument.children.find(
      (child) => child.sel === "head",
    );

    Hologram.virtualDocument.children = Hologram.virtualDocument.children.map(
      (child) => {
        switch (child.sel) {
          case "body":
            return patch(oldBody, newBody);

          case "head":
            return patch(oldHead, newHead);

          default:
            return child;
        }
      },
    );
  }

  static #replaceHistoryState() {
    const data = {
      componentRegistryEntries: ComponentRegistry.entries,
      pageModule: Hologram.#pageModule,
      pageParams: Hologram.#pageParams,
    };

    const id = crypto.randomUUID();
    PersistentStorage.putPageSnapshot(id, data);

    history.replaceState(id, null, window.location.pathname);
  }
}
