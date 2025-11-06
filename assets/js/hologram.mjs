"use strict";

import AssetPathRegistry from "./asset_path_registry.mjs";
import Bitstring from "./bitstring.mjs";
import Client from "./client.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Deserializer from "./deserializer.mjs";
import GlobalRegistry from "./global_registry.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import InitActionQueue from "./init_action_queue.mjs";
import Interpreter from "./interpreter.mjs";
import MemoryStorage from "./memory_storage.mjs";
import Operation from "./operation.mjs";
import PerformanceTimer from "./performance_timer.mjs";
import Renderer from "./renderer.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";
import Vdom from "./vdom.mjs";

// Events
import ChangeEvent from "./events/change_event.mjs";
import ClickEvent from "./events/click_event.mjs";
import FocusEvent from "./events/focus_event.mjs";
import InputEvent from "./events/input_event.mjs";
import MouseEvent from "./events/mouse_event.mjs";
import PointerEvent from "./events/pointer_event.mjs";
import SelectEvent from "./events/select_event.mjs";
import SubmitEvent from "./events/submit_event.mjs";
import TransitionEvent from "./events/transition_event.mjs";

import ManuallyPortedElixirCldrLocale from "./elixir/cldr/locale.mjs";
import ManuallyPortedElixirCldrValidityU from "./elixir/cldr/validity/u.mjs";
import ManuallyPortedElixirCode from "./elixir/code.mjs";
import ManuallyPortedElixirHologramJS from "./elixir/hologram/js.mjs";
import ManuallyPortedElixirHologramRouterHelpers from "./elixir/hologram/router/helpers.mjs";
import ManuallyPortedElixirIO from "./elixir/io.mjs";
import ManuallyPortedElixirKernel from "./elixir/kernel.mjs";
import ManuallyPortedElixirString from "./elixir/string.mjs";
import ManuallyPortedElixirURI from "./elixir/uri.mjs";

import {toVNode} from "snabbdom";

// TODO: test
export default class Hologram {
  static #PAGE_SNAPSHOT_KEY_PREFIX = "hologram_page_snapshot_";

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

  static #historyId = null;
  static #isInitiated = false;
  static #pageModule = null;
  static #pageParams = null;
  static #registeredPageModules = new Set();
  static #scrollPosition = null;
  static #shouldLoadMountData = true;

  // TODO: make private (tested implicitely in feature tests)
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

      Client.sendCommand(nextCommand);
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
      PerformanceTimer.diff(startTime),
    );

    Hologram.render();

    Hologram.#scheduleQueuedInitActions();

    if (!Type.isNil(nextAction)) {
      if (Type.isNil(Erlang_Maps["get/2"](Type.atom("target"), nextAction))) {
        nextAction = Erlang_Maps["put/3"](
          Type.atom("target"),
          target,
          nextAction,
        );
      }

      Hologram.scheduleAction(nextAction);
    }

    if (!Type.isNil(nextPage)) {
      $.#navigateToPage(nextPage);
    }
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
      Hologram.loadNewPage(pagePath, mapValue.html);
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

      Client.fetchPage(toParam, (resp) =>
        Hologram.handlePrefetchPageSuccess(mapKey, resp),
      );
    }
  }

  static handlePrefetchPageSuccess(mapKey, html) {
    const mapValue = Hologram.prefetchedPages.get(mapKey);

    if (typeof mapValue === "undefined") {
      return;
    }

    if (mapValue.isNavigateConfirmed) {
      Hologram.prefetchedPages.delete(mapKey);
      Hologram.loadNewPage(mapValue.pagePath, html);
    } else {
      mapValue.html = html;
    }
  }

  // Deps: [:maps.get/3]
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
        let delay;

        switch (Hologram.#getActionName(operation)) {
          case "__load_prefetched_page__":
            return Hologram.executeLoadPrefetchedPageAction(
              operation,
              event.target,
            );

          case "__prefetch_page__":
            return Hologram.executePrefetchPageAction(operation, event.target);

          default:
            delay = Erlang_Maps["get/3"](
              Type.atom("delay"),
              operation,
              Type.integer(0),
            );

            if (delay.value === 0n) {
              return Hologram.executeAction(operation);
            } else {
              return Hologram.scheduleAction(operation);
            }
        }
      } else {
        Client.sendCommand(operation);
      }
    }
  }

  // Made public to make tests easier
  static async loadNewPage(pagePath, html) {
    await $.#savePageSnapshot();
    $.#historyId = crypto.randomUUID();

    window.requestAnimationFrame(() => {
      Hologram.#patchPage(html);
      window.scrollTo(0, 0);

      history.pushState($.#historyId, null, pagePath);
    });
  }

  // Made public to make tests easier
  // Deps: [:maps.get/2, :maps.get/3, :maps.put/3]
  static queueActionsFromServerInits() {
    for (const [cid, entry] of Object.values(ComponentRegistry.entries.data)) {
      const componentStruct = Erlang_Maps["get/2"](Type.atom("struct"), entry);

      const nextAction = Erlang_Maps["get/3"](
        Type.atom("next_action"),
        componentStruct,
        Type.nil(),
      );

      if (!Type.isNil(nextAction)) {
        let actionWithTarget = nextAction;

        if (
          Type.isNil(
            Erlang_Maps["get/3"](Type.atom("target"), nextAction, Type.nil()),
          )
        ) {
          actionWithTarget = Erlang_Maps["put/3"](
            Type.atom("target"),
            cid,
            nextAction,
          );
        }

        InitActionQueue.enqueue(actionWithTarget);
      }
    }
  }

  // Made public to make tests easier
  static render() {
    const startTime = performance.now();

    const newVirtualDocument = Renderer.renderPage(
      Hologram.#pageModule,
      Hologram.#pageParams,
    );

    Hologram.virtualDocument = Vdom.patchVirtualDocument(
      Hologram.virtualDocument,
      newVirtualDocument,
    );

    console.log("Hologram: page rendered in", PerformanceTimer.diff(startTime));
  }

  static run() {
    Hologram.#onReady(async () => {
      if (!Hologram.#isInitiated) {
        await Hologram.#init();
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

  // Execute action asynchronously to allow animations and prevent blocking the event loop
  // Deps: [:maps.get/3]
  static scheduleAction(action) {
    const delay = Erlang_Maps["get/3"](
      Type.atom("delay"),
      action,
      Type.integer(0),
    );

    setTimeout(() => Hologram.executeAction(action), Number(delay.value));
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
      "Hologram.JS",
      "exec/1",
      "public",
      ManuallyPortedElixirHologramJS["exec/1"],
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
      "contains?/2",
      "public",
      ManuallyPortedElixirString["contains?/2"],
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
      "trim/1",
      "public",
      ManuallyPortedElixirString["trim/1"],
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

    Interpreter.defineManuallyPortedFunction(
      "URI",
      "encode/2",
      "public",
      ManuallyPortedElixirURI["encode/2"],
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
        return ClickEvent;

      case "input":
        return InputEvent;

      case "mousemove":
        return MouseEvent;

      case "pointercancel":
      case "pointerdown":
      case "pointermove":
      case "pointerup":
        return PointerEvent;

      case "select":
        return SelectEvent;

      case "submit":
        return SubmitEvent;

      case "transitioncancel":
      case "transitionend":
      case "transitionrun":
      case "transitionstart":
        return TransitionEvent;
    }
  }

  static async #getPageSnapshot(historyId) {
    const snapshotKey = $.#pageSnapshotKey(historyId);

    // Try OPFS first
    try {
      const root = await navigator.storage.getDirectory();
      const fileHandle = await root.getFileHandle(snapshotKey, {create: false});
      const file = await fileHandle.getFile();
      return await file.text();
    } catch {
      // Fall back to session storage if OPFS fails
      return sessionStorage.getItem(snapshotKey);
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
    await $.#savePageSnapshot();
    $.#historyId = event.state;

    const serializedPageSnapshot = await $.#getPageSnapshot(event.state);

    if (serializedPageSnapshot) {
      $.#restorePageSnapshot(serializedPageSnapshot);
    }

    if ($.#isPageModuleRegistered(Hologram.#pageModule)) {
      return $.#mountPage(true);
    }

    await Client.fetchPageBundlePath(
      Hologram.#pageModule,
      (resp) => {
        const script = document.createElement("script");
        script.src = resp;
        script.fetchpriority = "high";
        document.head.appendChild(script);
      },
      (_resp) => {
        throw new HologramRuntimeError(
          "Failed to fetch page bundle path for: " +
            Interpreter.inspect(Hologram.#pageModule),
        );
      },
    );
  }

  // Executed only once, on the initial page load.
  // Deps: [:maps.get/2]
  static async #init() {
    // TODO: consider when implementing boxed error handling
    // window.addEventListener("error", (event) => {
    //   if (event.error instanceof HologramBoxedError) {
    //     console.error(`${event.error.message}\n`, event.error);
    //     event.preventDefault();
    //   }
    // });

    window.addEventListener("error", (event) => {
      if (event.error instanceof HologramBoxedError) {
        GlobalRegistry.set("lastBoxedError", {
          module: Interpreter.inspect(
            Erlang_Maps["get/2"](Type.atom("__struct__"), event.error.struct),
          ),
          message: Bitstring.toText(
            Erlang_Maps["get/2"](Type.atom("message"), event.error.struct),
          ),
        });
      }
    });

    window.addEventListener("beforeunload", () => {
      // Force synchronous session storage save since async OPFS may not complete before page termination
      Hologram.#savePageSnapshot(true);
    });

    window.addEventListener("popstate", Hologram.#handlePopstateEvent);

    window.addEventListener("pageshow", (event) => {
      // Reconnect when page is restored from bfcache OR when navigating back from external page
      if (event.persisted || !Client.isConnected()) {
        Client.connect(true);
      }
    });

    // Check if there's already a history state (e.g., when navigating back from external page)
    if (history.state) {
      $.#historyId = history.state;
      const serializedPageSnapshot = await $.#getPageSnapshot(history.state);

      // Only restore state for back/forward navigation, not page reloads
      if (!$.#isPageReload() && serializedPageSnapshot) {
        $.#restorePageSnapshot(serializedPageSnapshot);
      }
    } else {
      $.#historyId = crypto.randomUUID();
      history.replaceState($.#historyId, null, window.location.pathname);
    }

    Client.connect(false);

    Hologram.#defineManuallyPortedFunctions();

    Hologram.virtualDocument = toVNode(document.documentElement);
    Vdom.addKeysToLinkAndScriptVnodes(Hologram.virtualDocument);

    console.inspect = (term) => console.log(Interpreter.inspect(term));

    Hologram.#isInitiated = true;
  }

  static #isPageModuleRegistered(pageModule) {
    return $.#registeredPageModules.has(pageModule.value);
  }

  // Note: Although using the History API makes it impossible to use the Performance API for detecting
  // what was the last navigation type, when the page is reloaded the navigation type will
  // always be "reload". But the type remains the same for succeeding navigation types within
  // Hologram navigation, hence the additional check for whether the app was already initiated.
  // In case of the new Performance API, there will always be only one entry due to History API use.
  static #isPageReload() {
    // New Performance API
    if ("getEntriesByType" in performance) {
      return (
        !$.#isInitiated &&
        performance.getEntriesByType("navigation")[0].type === "reload"
      );
    }

    // Old Performance API
    return (
      !$.#isInitiated &&
      performance.navigation.type === PerformanceNavigation.TYPE_RELOAD
    );
  }

  static #isPrefetchPageTimedOut(mapKey) {
    return (
      Date.now() - Hologram.prefetchedPages.get(mapKey).timestamp >
      Config.fetchPageTimeoutMs
    );
  }

  static #loadMountData() {
    const mountData = globalThis.hologram.pageMountData(Hologram.#deps);

    Hologram.#pageModule = mountData.pageModule;
    Hologram.#pageParams = mountData.pageParams;

    ComponentRegistry.populate(mountData.componentRegistry);
  }

  static #maybeInitAssetPathRegistry() {
    if (AssetPathRegistry.entries === null) {
      AssetPathRegistry.populate(globalThis.hologram.assetManifest);
    }
  }

  static #mountPage(isPageModuleRegistered = false) {
    if ($.#shouldLoadMountData) {
      Hologram.#loadMountData();
    } else {
      $.#shouldLoadMountData = true;
    }

    if (!isPageModuleRegistered) {
      globalThis.hologram.pageReachableFunctionDefs(Hologram.#deps);
      $.#registerPageModule($.#pageModule);
    }

    Hologram.#maybeInitAssetPathRegistry();

    Hologram.prefetchedPages.clear();

    Hologram.queueActionsFromServerInits();

    window.requestAnimationFrame(() => {
      $.render();

      if ($.#scrollPosition) {
        window.scrollTo($.#scrollPosition[0], $.#scrollPosition[1]);
        $.#scrollPosition = null;
      }

      GlobalRegistry.set("mountedPage", Interpreter.inspect($.#pageModule));

      Hologram.#scheduleQueuedInitActions();
    });
  }

  // Tested implicitely in feature tests
  static async #navigateToPage(toParam) {
    const pagePath = $.#buildPagePath(toParam);

    return Client.fetchPage(toParam, (resp) =>
      Hologram.loadNewPage(pagePath, resp),
    );
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

  static #pageSnapshotKey(historyId) {
    return `${$.#PAGE_SNAPSHOT_KEY_PREFIX}${historyId}`;
  }

  // TODO: raise error if there is no head or body
  static #patchPage(html) {
    globalThis.hologram.pageScriptLoaded = false;

    const newVirtualDocument = Vdom.from(html);

    Hologram.virtualDocument = Vdom.patchVirtualDocument(
      Hologram.virtualDocument,
      newVirtualDocument,
    );
  }

  static #registerPageModule(pageModule) {
    $.#registeredPageModules.add(pageModule.value);
  }

  static #restorePageSnapshot(serializedPageSnapshot) {
    const {componentRegistryEntries, pageModule, pageParams, scrollPosition} =
      Deserializer.deserialize(serializedPageSnapshot);

    ComponentRegistry.populate(componentRegistryEntries);

    Hologram.#pageModule = pageModule;
    Hologram.#pageParams = pageParams;

    $.#scrollPosition = scrollPosition;
    $.#shouldLoadMountData = false;
  }

  static async #savePageSnapshot(forceSync = false) {
    const serializedPageSnapshot = Serializer.serialize(
      {
        componentRegistryEntries: ComponentRegistry.entries,
        pageModule: Hologram.#pageModule,
        pageParams: Hologram.#pageParams,
        scrollPosition: [window.scrollX, window.scrollY],
      },
      "client",
    );

    const snapshotKey = $.#pageSnapshotKey($.#historyId);

    // For beforeunload: save synchronously to session storage only
    if (forceSync) {
      try {
        sessionStorage.setItem(snapshotKey, serializedPageSnapshot);
      } catch (error) {
        console.error(
          "Failed to save page snapshot to session storage:",
          error,
        );
      }

      return;
    }

    // For normal navigation: OPFS primary, session storage fallback
    try {
      const root = await navigator.storage.getDirectory();
      const fileHandle = await root.getFileHandle(snapshotKey, {create: true});
      const writable = await fileHandle.createWritable();
      await writable.write(serializedPageSnapshot);
      await writable.close();

      // Successfully saved to OPFS, clear session storage fallback if it exists
      sessionStorage.removeItem(snapshotKey);
    } catch (opfsError) {
      console.error("Failed to save page snapshot to OPFS:", opfsError);

      // Fallback to session storage if OPFS fails
      try {
        sessionStorage.setItem(snapshotKey, serializedPageSnapshot);
      } catch (sessionStorageError) {
        console.error(
          "Failed to save page snapshot to session storage:",
          sessionStorageError,
        );
      }
    }
  }

  static #scheduleQueuedInitActions() {
    const actions = InitActionQueue.dequeueAll();

    actions.forEach((action) => {
      Hologram.scheduleAction(action);
    });
  }
}

const $ = Hologram;
