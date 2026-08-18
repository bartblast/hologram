"use strict";

import App from "./app.mjs";
import AssetPathRegistry from "./asset_path_registry.mjs";
import Bitstring from "./bitstring.mjs";
import Client from "./client.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Debouncer from "./debouncer.mjs";
import Deserializer from "./deserializer.mjs";
import ERTS from "./erts.mjs";
import EventListenerRegistry from "./event_listener_registry.mjs";
import EventListeners from "./event_listeners.mjs";
import GlobalRegistry from "./global_registry.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import InitActionQueue from "./init_action_queue.mjs";
import Interpreter from "./interpreter.mjs";
import JsInterop from "./js_interop.mjs";
import MemoryStorage from "./memory_storage.mjs";
import Operation from "./operation.mjs";
import PerformanceTimer from "./performance_timer.mjs";
import Renderer from "./renderer.mjs";
import Serializer from "./serializer.mjs";
import Sse from "./sse.mjs";
import Throttler from "./throttler.mjs";
import Type from "./type.mjs";
import UncaughtErrorOverlay from "./uncaught_error_overlay.mjs";
import Utils from "./utils.mjs";
import Vdom from "./vdom.mjs";

// Events
import ChangeEvent from "./events/change_event.mjs";
import ClickEvent from "./events/click_event.mjs";
import ClickOutsideEvent from "./events/click_outside_event.mjs";
import FocusEvent from "./events/focus_event.mjs";
import InputEvent from "./events/input_event.mjs";
import KeyboardEvent from "./events/keyboard_event.mjs";
import MouseEvent from "./events/mouse_event.mjs";
import PointerEvent from "./events/pointer_event.mjs";
import ReachEvent from "./events/reach_event.mjs";
import ResizeEvent from "./events/resize_event.mjs";
import ScrollEvent from "./events/scroll_event.mjs";
import SelectEvent from "./events/select_event.mjs";
import SubmitEvent from "./events/submit_event.mjs";
import TransitionEvent from "./events/transition_event.mjs";

import ManuallyPortedElixirApplication from "./elixir/application.mjs";
import ManuallyPortedElixirCldrLocale from "./elixir/cldr/locale.mjs";
import ManuallyPortedElixirCldrValidityU from "./elixir/cldr/validity/u.mjs";
import ManuallyPortedElixirCode from "./elixir/code.mjs";
import ManuallyPortedElixirException from "./elixir/exception.mjs";
import ManuallyPortedElixirFunctionClauseError from "./elixir/function_clause_error.mjs";
import ManuallyPortedElixirHologramJS from "./elixir/hologram/js.mjs";
import ManuallyPortedElixirHologramRouterHelpers from "./elixir/hologram/router/helpers.mjs";
import ManuallyPortedElixirIO from "./elixir/io.mjs";
import ManuallyPortedElixirKernel from "./elixir/kernel.mjs";
import ManuallyPortedElixirString from "./elixir/string.mjs";
import ManuallyPortedElixirStringTokenizer from "./elixir/string/tokenizer.mjs";
import ManuallyPortedElixirTask from "./elixir/task.mjs";
import ManuallyPortedElixirURI from "./elixir/uri.mjs";

// TODO: test
export default class Hologram {
  static #ETS_STORAGE_KEY = "hologram_ets";

  // A redirect can point at a page that redirects again, so a cycle would fetch forever without a
  // limit. Browsers stop at 20; this is lower because these hops are page renders, not lookups.
  static #MAX_REDIRECT_HOPS = 10;

  static #PAGE_SNAPSHOT_KEY_PREFIX = "hologram_page_snapshot_";

  // Made public to make tests easier
  static prefetchedPages = new Map();

  // Made public to make tests easier
  static virtualDocument = null;

  static #deps = {
    Bitstring: Bitstring,
    ERTS: ERTS,
    HologramBoxedError: HologramBoxedError,
    HologramInterpreterError: HologramInterpreterError,
    Interpreter: Interpreter,
    MemoryStorage: MemoryStorage,
    Type: Type,
    Utils: Utils,
  };

  // In-memory cache for page snapshots (fastest access)
  static #pageSnapshots = new Map();

  static #historyId = null;
  static #isInitiated = false;
  static #isMountPending = false;
  static #pageModule = null;
  static #pageParams = null;
  static #pendingJsInteropActions = [];
  static #preMountActions = [];
  static #registeredPageModules = new Set();
  static #scheduledActionTimerIds = new Set();
  static #scrollPosition = null;
  static #shouldLoadMountData = true;

  // Clears every action still waiting on its timer without executing any of them, mirroring
  // Debouncer.cancelAll()/Throttler.cancelAll(). Every action is scheduled onto a timer, even at
  // delay 0, so a dispatch decided in one page's context is always in flight for at least a
  // macrotask - long enough to outlive the context it was meant for.
  static cancelScheduledActions() {
    for (const timerId of $.#scheduledActionTimerIds) {
      clearTimeout(timerId);
    }

    $.#scheduledActionTimerIds.clear();
  }

  // Public API for dispatching actions from JavaScript.
  // Converts plain JS values to Hologram types and schedules the action for execution.
  // Example: globalThis.Hologram.dispatchAction("increment", "page", {amount: 5})
  static dispatchAction(actionName, target, params = {}) {
    const action = Type.actionStruct({
      name: Type.atom(actionName),
      params: JsInterop.boxActionParam(params),
      target: Type.bitstring(target),
    });

    // Everything arriving here comes from script the page itself carries, so it belongs to the
    // page on screen. Between a page swap starting and the new page mounting that page is the
    // destination - its markup is patched in and its scripts have run - while the registry still
    // answers for the page being left, so dispatching now would resolve against the wrong page.
    // The action waits instead, until the destination can answer for it.
    if ($.#isMountPending) {
      $.#preMountActions.push(action);
      return;
    }

    Hologram.scheduleAction(action);
  }

  // This function is intentionally NOT async. Actions that use Task.await/1 return
  // a Promise, but we handle it with .then() instead of async/await. Making this
  // function async would wrap ALL errors (including from sync actions) in rejected
  // Promises, breaking ChromeDriver/Wallaby error detection which relies on the
  // synchronous "error" event. Async action errors are caught separately via the
  // "unhandledrejection" event listener in #init().
  // TODO: make private (tested implicitely in feature tests)
  // Deps: [:maps.get/2]
  static executeAction(action) {
    const startTime = performance.now();
    globalThis.Hologram.isProfilingEnabled = true;

    const name = Erlang_Maps["get/2"](Type.atom("name"), action);
    const params = Erlang_Maps["get/2"](Type.atom("params"), action);
    const target = Erlang_Maps["get/2"](Type.atom("target"), action);

    // getComponentModule() answers with plain null for a cid the registry does not hold, and null
    // reaching callNamedFunction faults on reading a module name off it - a raw TypeError naming
    // neither the cid nor the action, which handleUncaughtError drops because it isn't boxed.
    // Pending dispatches are cancelled at both registry swaps, so a target the registry never held
    // is a mistyped cid and nothing else - raised boxed, the way the error overlay reads it.
    if (!ComponentRegistry.isCidRegistered(target)) {
      Interpreter.raiseArgumentError(
        `invalid action target, there is no component with CID: ${Interpreter.inspect(target)}`,
      );
    }

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

    if (resultComponentStruct instanceof Promise) {
      resultComponentStruct.then((resolved) =>
        Hologram.#processActionResult(resolved, name, target, startTime),
      );
    } else {
      Hologram.#processActionResult(
        resultComponentStruct,
        name,
        target,
        startTime,
      );
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

    if (mapValue.isPage === false) {
      Hologram.prefetchedPages.delete(mapKey);
      Hologram.leaveApp(pagePath);
    } else if (mapValue.payload === null) {
      mapValue.isNavigateConfirmed = true;
    } else {
      Hologram.prefetchedPages.delete(mapKey);
      Hologram.loadNewPage(pagePath, mapValue.payload);
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
        isNavigateConfirmed: false,
        isPage: true,
        pagePath: pagePath,
        payload: null,
        timestamp: Date.now(),
      });

      // A prefetch keeps whatever the server described, a page or a redirect, and acts on it only
      // once the user commits to going there - following a redirect on hover would fetch pages
      // nobody asked for.
      Client.fetchPage(
        toParam,
        (payload) => Hologram.handlePrefetchPageSuccess(mapKey, payload),
        () => Hologram.handlePrefetchPageNotPage(mapKey),
      );
    }
  }

  // Made public to make tests easier
  //
  // What a prefetch found instead of a page: a denial, or a response the page's middleware wrote
  // itself. The entry is kept rather than dropped, because a click looks the target up here and
  // would otherwise find nothing and do nothing at all, leaving the link dead.
  static handlePrefetchPageNotPage(mapKey) {
    const mapValue = Hologram.prefetchedPages.get(mapKey);

    if (typeof mapValue === "undefined") {
      return;
    }

    if (mapValue.isNavigateConfirmed) {
      Hologram.prefetchedPages.delete(mapKey);
      Hologram.leaveApp(mapValue.pagePath);
    } else {
      mapValue.isPage = false;
    }
  }

  static handlePrefetchPageSuccess(mapKey, payload) {
    const mapValue = Hologram.prefetchedPages.get(mapKey);

    if (typeof mapValue === "undefined") {
      return;
    }

    if (mapValue.isNavigateConfirmed) {
      Hologram.prefetchedPages.delete(mapKey);
      Hologram.loadNewPage(mapValue.pagePath, payload);
    } else {
      mapValue.payload = payload;
    }
  }

  // Processes a UI event and returns a dispatch function that runs the resulting action or
  // command, or null when the binding is disabled or the event is ignored. The edge concerns
  // that must happen during the event itself - the disabled-binding check, the ignored-event
  // check, preventDefault, stopPropagation, and reading the event payload (the browser nulls
  // currentTarget once dispatch returns) - run synchronously here. Callers invoke the returned
  // dispatch immediately, or hand it to the debouncer so that only the dispatch is deferred
  // while preventDefault still takes effect on every event.
  // Deps: [:maps.get/3]
  static handleUiEvent(
    event,
    eventType,
    operationSpecDom,
    defaultTarget,
    allowDefault = false,
    stopPropagation = false,
    forcePreventDefault = false,
  ) {
    // The guard runs before preventDefault and stopPropagation, so a disabled binding leaves
    // native browser behavior fully untouched.
    if (Operation.isDisabled(operationSpecDom)) {
      return null;
    }

    const eventImpl = Hologram.#getEventImplementation(eventType);

    if (eventImpl.isEventIgnored(event)) {
      return null;
    }

    // allowDefault is the binding's allow_default modifier: it opts this binding out of the
    // framework's preventDefault so the browser's native default proceeds. forcePreventDefault is
    // the binding's prevent_default modifier: it forces preventDefault even on events that allow
    // the default by design (above all keyboard events). Optional call: some event payloads are
    // not DOM events and have no preventDefault method, e.g. a resize binding's ResizeObserverEntry.
    if (forcePreventDefault || (!eventImpl.isDefaultAllowed && !allowDefault)) {
      event.preventDefault?.();
    }

    // stopPropagation is the binding's stop_propagation modifier: it stops the event from
    // bubbling past the bound element, so ancestor and document/window listeners do not fire.
    // Optional call: some event payloads are not DOM events and have no stopPropagation method,
    // e.g. a resize binding's ResizeObserverEntry.
    if (stopPropagation) {
      event.stopPropagation?.();
    }

    const eventParam = eventImpl.buildOperationParam(event);
    const eventTarget = event.target;

    return () => {
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
              eventTarget,
            );

          case "__prefetch_page__":
            return Hologram.executePrefetchPageAction(operation, eventTarget);

          default: {
            const delay = Erlang_Maps["get/3"](
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
        }
      } else {
        Client.sendCommand(operation);
      }
    };
  }

  // Records an uncaught boxed error and puts it in the page.
  //
  // Nothing is written to the console here: the error carries the whole report
  // as its message, so the entry the browser writes for an error nobody caught
  // holds the Elixir frames and the JavaScript stack below them - one entry,
  // and its stack stays the structured one the devtools resolve through the
  // bundle's source maps.
  static handleUncaughtError(error) {
    if (!(error instanceof HologramBoxedError)) {
      return;
    }

    // Read by the feature test helpers, which assert against the error the
    // page last raised. Both parts are taken as the error derived them, so an
    // error that failed to derive is still reported, with the fault named.
    GlobalRegistry.set("lastBoxedError", {
      module: error.type,
      message: error.text,
    });

    if (globalThis.Hologram.config.errorOverlay) {
      UncaughtErrorOverlay.show(error);
    }
  }

  // Made public to make tests easier
  //
  // Gives the path back to the browser, which is how Hologram answers anything it cannot mount: a
  // target outside the app, or a response a page's middleware wrote itself. The browser then gets
  // the same answer a typed-in URL would have got, address bar and history included.
  static leaveApp(url) {
    window.location.assign(url);
  }

  // Made public to make tests easier
  //
  // Takes the page the server described, or where it says to go instead. A redirect is followed by
  // asking for the page it names, so only the page actually arrived at is mounted and only its path
  // enters history - the same trail a browser leaves, where the pages passed through on the way are
  // not places the user can go back to.
  static async loadNewPage(pagePath, payload, hopCount = 0) {
    if (payload.type === "redirect") {
      return Hologram.#followRedirect(payload, hopCount);
    }

    await $.#savePageSnapshot();
    $.#historyId = Utils.randomUUID();

    window.requestAnimationFrame(() => {
      Hologram.#showNewPage(payload);
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
        ComponentRegistry.clearNextAction(cid);

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
  static queueSelfEchoes(selfEchoes) {
    for (const action of selfEchoes.data) {
      InitActionQueue.enqueue(action);
    }
  }

  // Made public to make tests easier
  static render() {
    const startTime = performance.now();

    const newVirtualDocument = Renderer.renderPage(
      Hologram.#pageModule,
      Hologram.#pageParams,
    );

    // On a full document load there is no previous render to diff against, only the page the
    // server sent, so the old side is built by mirroring this render onto it. The patch then
    // adopts those nodes instead of recreating the whole page.
    if (Hologram.virtualDocument === null) {
      Hologram.virtualDocument = Vdom.mirror(
        newVirtualDocument,
        document.documentElement,
      );
    }

    Hologram.virtualDocument = Vdom.patchVirtualDocument(
      Hologram.virtualDocument,
      newVirtualDocument,
    );

    // renderPage() collected this render's <window>/<document> bindings into Renderer.listenerBindings
    // and its deferred element bindings (reach, resize) into Renderer.reachBindings and
    // Renderer.resizeBindings. Now that the DOM is patched, reconcile them into real listeners on
    // their targets. The deferred bindings are resolved here because their target is a live DOM
    // element, which exists only after patch. Each resolve also drops a binding whose once modifier
    // has fired, so reconcile tears it down. Every page-entry path reaches render() through
    // #mountPage, so this also tears down a previous page's listeners on navigation.
    EventListenerRegistry.reconcile([
      ...Renderer.resolveListenerBindings(),
      ...Renderer.resolveReachBindings(),
      ...Renderer.resolveResizeBindings(),
    ]);

    // Reach listeners persist across renders, so reconcile alone does not re-run them. Recheck them
    // now that the DOM is patched, so each re-syncs the children it watches and recomputes - firing
    // again as content this render added extends or fills the container.
    EventListeners.recheckScrollEdges();

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
          error.name = error.type;
          error.message = error.text;
        }

        throw error;
      }

      // SSE must open AFTER `#mountPage()` because the handshake payload
      // includes the receipts merged from `pageMountData.subReceiptAdds` -
      // connecting earlier would send an empty receipts list.
      if (Sse.eventSource === null) {
        Sse.connect();
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

    // The id is dropped before the action runs rather than after, so an action that raises
    // doesn't leave a fired timer's id behind for a later cancellation to clear.
    const timerId = setTimeout(() => {
      $.#scheduledActionTimerIds.delete(timerId);
      Hologram.executeAction(action);
    }, Number(delay.value));

    $.#scheduledActionTimerIds.add(timerId);
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
      "Application",
      "get_env/3",
      "public",
      ManuallyPortedElixirApplication["get_env/3"],
    );

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
      "Code",
      "ensure_loaded/1",
      "public",
      ManuallyPortedElixirCode["ensure_loaded/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Exception",
      "format_stacktrace/1",
      "public",
      ManuallyPortedElixirException["format_stacktrace/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "FunctionClauseError",
      "message/1",
      "public",
      ManuallyPortedElixirFunctionClauseError["message/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "call/4",
      "public",
      ManuallyPortedElixirHologramJS["call/4"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "delete/3",
      "public",
      ManuallyPortedElixirHologramJS["delete/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "dispatch_event/5",
      "public",
      ManuallyPortedElixirHologramJS["dispatch_event/5"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "eval/1",
      "public",
      ManuallyPortedElixirHologramJS["eval/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "exec/1",
      "public",
      ManuallyPortedElixirHologramJS["exec/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "get/3",
      "public",
      ManuallyPortedElixirHologramJS["get/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "instanceof/3",
      "public",
      ManuallyPortedElixirHologramJS["instanceof/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "new/3",
      "public",
      ManuallyPortedElixirHologramJS["new/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "set/4",
      "public",
      ManuallyPortedElixirHologramJS["set/4"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.JS",
      "typeof/2",
      "public",
      ManuallyPortedElixirHologramJS["typeof/2"],
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
      "IO",
      "warn/1",
      "public",
      ManuallyPortedElixirIO["warn/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "IO",
      "warn/2",
      "public",
      ManuallyPortedElixirIO["warn/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "IO",
      "warn_once/3",
      "public",
      ManuallyPortedElixirIO["warn_once/3"],
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
      "String.Tokenizer",
      "tokenize/1",
      "public",
      ManuallyPortedElixirStringTokenizer["tokenize/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Task",
      "await/1",
      "public",
      ManuallyPortedElixirTask["await/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "URI",
      "encode/2",
      "public",
      ManuallyPortedElixirURI["encode/2"],
    );
  }

  static #dispatchPendingJsInteropActions() {
    const actions = Hologram.#pendingJsInteropActions;
    Hologram.#pendingJsInteropActions = [];

    actions.forEach(([actionName, target, params]) => {
      Hologram.dispatchAction(actionName, target, params);
    });
  }

  // Takes the page's own bundle out of the document the server described, leaving every other
  // script it carries to be patched in and run.
  //
  // The bundle is fetched here rather than through the patch so that a failure to load is
  // noticed - #loadPageBundle gives it a failure path, which a script the patch creates would
  // not have. It also settles what a script element cannot express on its own: a script is keyed
  // by the source it loads, so navigating back to a page whose bundle is already in the document
  // would adopt that element and never run it, while navigating to a page whose bundle is in
  // memory but absent from the document would run it a second time.
  //
  // The document is the one just built from the tree, so it is edited in place.
  static #dropPageBundleScript(virtualDocument, pageDigest) {
    // Mirrors Hologram.Router.Helpers.page_bundle_path/1
    const key = `__hologramScript__:${$.#pageBundlePath(pageDigest)}`;

    const headVnode = virtualDocument.children.find(
      (childVnode) => childVnode?.sel === "head",
    );

    if (headVnode) {
      headVnode.children = headVnode.children.filter(
        (childVnode) => childVnode?.key !== key,
      );
    }
  }

  static #ensureDomNodeHasHologramId(eventNode) {
    if (typeof eventNode.__hologramId__ === "undefined") {
      eventNode.__hologramId__ = Utils.randomUUID();
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

      case "click_outside":
        return ClickOutsideEvent;

      case "input":
        return InputEvent;

      case "keydown":
      case "keyup":
        return KeyboardEvent;

      case "mousemove":
        return MouseEvent;

      case "pointercancel":
      case "pointerdown":
      case "pointermove":
      case "pointerup":
        return PointerEvent;

      case "reach_bottom":
      case "reach_left":
      case "reach_right":
      case "reach_top":
        return ReachEvent;

      case "resize":
        return ResizeEvent;

      case "scroll":
        return ScrollEvent;

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

    // Try in-memory cache first (fastest) - returns deserialized object
    if ($.#pageSnapshots.has(snapshotKey)) {
      return $.#pageSnapshots.get(snapshotKey);
    }

    // Try OPFS second
    try {
      const root = await navigator.storage.getDirectory();
      const fileHandle = await root.getFileHandle(snapshotKey, {create: false});
      const file = await fileHandle.getFile();
      const serializedSnapshot = await file.text();
      const deserializedSnapshot = Deserializer.deserialize(serializedSnapshot);

      // Cache the deserialized snapshot in memory for faster subsequent access
      $.#pageSnapshots.set(snapshotKey, deserializedSnapshot);

      return deserializedSnapshot;
    } catch {
      // Fall back to session storage if OPFS fails
      const serializedSnapshot = sessionStorage.getItem(snapshotKey);

      if (serializedSnapshot) {
        const deserializedSnapshot =
          Deserializer.deserialize(serializedSnapshot);

        // Cache the deserialized snapshot in memory for faster subsequent access
        $.#pageSnapshots.set(snapshotKey, deserializedSnapshot);

        return deserializedSnapshot;
      }

      return null;
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
    // The history's side of the boundary #showNewPage guards: everything below belongs to the
    // page being restored, so this is the last instant at which every pending dispatch provably
    // belongs to the page being left. The restore below is skipped when there is no snapshot, so
    // this cannot live there.
    Hologram.cancelScheduledActions();

    await $.#savePageSnapshot();
    $.#historyId = event.state;

    const pageSnapshot = await $.#getPageSnapshot(event.state);

    if (pageSnapshot) {
      $.#restorePageSnapshot(pageSnapshot);
    }

    if ($.#isPageModuleRegistered(Hologram.#pageModule)) {
      return $.#mountPage(true);
    }

    await Client.fetchPageBundlePath(
      Hologram.#pageModule,
      (resp) => $.#loadPageBundle(resp),
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
    window.addEventListener("error", (event) => {
      $.handleUncaughtError(event.error);
    });

    // Async action errors surface as rejected Promises (from the .then() path
    // in executeAction) and fire "unhandledrejection" instead of "error".
    window.addEventListener("unhandledrejection", (event) => {
      $.handleUncaughtError(event.reason);
    });

    window.addEventListener("beforeunload", () => {
      // Force synchronous session storage save since async OPFS may not complete before page termination
      Hologram.#savePageSnapshot(true);

      Hologram.#saveEts();
    });

    window.addEventListener("popstate", Hologram.#handlePopstateEvent);

    window.addEventListener("pageshow", (event) => {
      // Reconnect when page is restored from bfcache OR when navigating back from external page
      if (event.persisted || !Client.isConnected()) {
        Client.connect(true);
      }
    });

    // Losing focus definitively ends any burst of events from an element, so its pending
    // debounced dispatches fire now instead of waiting out the rest of their windows.
    document.addEventListener("focusout", (event) =>
      Debouncer.flush(event.target),
    );

    // Submit is a commit point: everything entered into the form is logically before it, so the
    // form's pending debounced dispatches run first. Capture phase guarantees the flush precedes
    // the form's own bound handler reading the event payload and dispatching.
    document.addEventListener(
      "submit",
      (event) => Debouncer.flushWithin(event.target),
      true,
    );

    // Check if there's already a history state (e.g., when navigating back from external page)
    if (history.state) {
      $.#historyId = history.state;
      const pageSnapshot = await $.#getPageSnapshot(history.state);

      // Only restore state for back/forward navigation, not page reloads
      if (!$.#isPageReload() && pageSnapshot) {
        $.#restorePageSnapshot(pageSnapshot);
      }
    } else {
      $.#historyId = Utils.randomUUID();
      history.replaceState($.#historyId, null, window.location.pathname);
    }

    await $.#restoreEts();

    App.maybeLoadInstanceId();
    Client.connect(false);

    Hologram.#defineManuallyPortedFunctions();

    // virtualDocument stays null here: the first render() mirrors itself onto the server's DOM,
    // which is what makes those nodes survive the first patch. Reading the page into a vdom of
    // its own instead would describe it in terms the render never uses - the keys it carries are
    // the render's, not the markup's - and every node would fail to match and be rebuilt.

    console.inspect = (term) => console.log(Interpreter.inspect(term));

    $.#pendingJsInteropActions = globalThis.Hologram._pendingJsInteropActions;
    globalThis.Hologram.dispatchAction = $.dispatchAction;
    delete globalThis.Hologram._pendingJsInteropActions;

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

  // What the page was mounted with, left behind by the script the server wrote into the page.
  // A navigation reaches it the same way a document load does, by patching in the page the
  // server described, that script included.
  static #loadMountData() {
    const mountData = globalThis.Hologram.pageMountData(Hologram.#deps);

    Hologram.#pageModule = mountData.pageModule;
    Hologram.#pageParams = mountData.pageParams;

    ComponentRegistry.populate(mountData.componentRegistry);

    return mountData;
  }

  // Fetches a page's own code. Running it is what announces the page is ready to mount, by
  // dispatching hologram:pageScriptLoaded, which the runtime listens for.
  //
  // Without the failure path a bundle that never loads ends the navigation in silence: nothing
  // dispatches the event, so the mount never runs, the URL is never pushed, and the page already
  // on screen stays with no sign that anything went wrong.
  //
  // Throwing from the handler does not reach whoever started the navigation, since the handler
  // runs off the event loop. It surfaces as an uncaught error instead, which is what the console
  // and the feature tests read. handleUncaughtError/1 passes it over rather than showing the
  // overlay, that being reserved for errors a page raised.
  static #loadPageBundle(src) {
    const script = document.createElement("script");

    script.src = src;
    script.fetchpriority = "high";

    script.onerror = () => {
      throw new HologramRuntimeError(`Failed to load page bundle: ${src}`);
    };

    document.head.appendChild(script);
  }

  static #maybeInitAssetPathRegistry() {
    if (AssetPathRegistry.entries === null) {
      AssetPathRegistry.populate(globalThis.Hologram.assetManifest);
    }
  }

  static #mountPage(isPageModuleRegistered = false) {
    // Cleared before the mount's own work, so everything it schedules is armed normally and the
    // release below does not simply hold the same actions again.
    $.#isMountPending = false;

    // Every page-entry path funnels through here (client-side navigation, back/forward
    // restoration, initial mount), so this is where dispatches still pending from the previous
    // page are dropped - the context they were meant for no longer exists. Cancel, not flush: a
    // dispatch must never execute on a page the user has left. On the initial mount both
    // cancellations are no-ops.
    Debouncer.cancelAll();
    Throttler.cancelAll();

    let mountData = null;

    if ($.#shouldLoadMountData) {
      mountData = Hologram.#loadMountData();
    } else {
      $.#shouldLoadMountData = true;
    }

    if (!isPageModuleRegistered) {
      globalThis.Hologram.pageReachableFunctionDefs(Hologram.#deps);
      $.#registerPageModule($.#pageModule);
    }

    Hologram.#maybeInitAssetPathRegistry();

    Hologram.prefetchedPages.clear();

    Hologram.queueActionsFromServerInits();

    if (mountData) {
      Hologram.queueSelfEchoes(mountData.selfEchoes);

      App.subscriptionReceiptRegistry.merge(
        mountData.subReceiptAdds,
        mountData.subReceiptDrops,
      );
    }

    window.requestAnimationFrame(() => {
      $.render();

      if ($.#scrollPosition) {
        window.scrollTo($.#scrollPosition[0], $.#scrollPosition[1]);
        $.#scrollPosition = null;
      }

      GlobalRegistry.set("mountedPage", Interpreter.inspect($.#pageModule));

      Hologram.#scheduleQueuedInitActions();
      Hologram.#dispatchPendingJsInteropActions();
      Hologram.#scheduleHeldActions();
    });
  }

  // Tested implicitely in feature tests
  static async #navigateToPage(toParam) {
    const pagePath = $.#buildPagePath(toParam);

    return Client.fetchPage(
      toParam,
      (payload) => Hologram.loadNewPage(pagePath, payload),
      () => Hologram.leaveApp(pagePath),
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

  // Mirrors Hologram.Router.Helpers.page_bundle_path/1
  static #pageBundlePath(pageDigest) {
    return `/hologram/page-${pageDigest}.js`;
  }

  static #pageSnapshotKey(historyId) {
    return `${$.#PAGE_SNAPSHOT_KEY_PREFIX}${historyId}`;
  }

  // Goes where a page's middleware said to go instead, by asking for the page it named.
  //
  // A target outside the app carries no page to ask for, so the browser takes it. The hop limit is
  // there because a redirect can point at a page that redirects again: a cycle would otherwise
  // fetch forever, silently.
  static #followRedirect(payload, hopCount) {
    if (!payload.pageModule) {
      Hologram.leaveApp(payload.to);
      return null;
    }

    if (hopCount >= $.#MAX_REDIRECT_HOPS) {
      throw new HologramRuntimeError(
        `Too many redirects (over ${$.#MAX_REDIRECT_HOPS}), last one to: ${payload.to}`,
      );
    }

    const toParam = Type.tuple([
      Interpreter.evaluateJavaScriptExpression(payload.pageModule),
      Interpreter.evaluateJavaScriptExpression(payload.pageParams),
    ]);

    return Client.fetchPage(
      toParam,
      (nextPayload) =>
        Hologram.loadNewPage(payload.to, nextPayload, hopCount + 1),
      () => Hologram.leaveApp(payload.to),
    );
  }

  // Puts the page the server described on screen, before any of that page's own code has arrived.
  //
  // The payload carries the render the server performed, so patching it into the document shows
  // the page a round trip after it was asked for, rather than a round trip plus a bundle plus a
  // render. What the patch puts on screen is inert - the tree carries no event bindings - until
  // the mount below renders the page for itself and adopts these nodes, which is what the keys
  // both renders agree on are for.
  //
  // The scripts the server would have served with the page ride in the tree and are patched in
  // with everything else, so the inline script leaving the mount data behind runs here, the same
  // way it runs when the browser loads a document. The page's own bundle is the exception, taken
  // out by #dropPageBundleScript.
  //
  // A page this client has already run needs no bundle at all, so it mounts as soon as the patch
  // is done. Otherwise the bundle is fetched, and running it announces the page is ready to
  // mount.
  static #showNewPage(payload) {
    // The patch below puts the destination on screen and runs any script it carries, and for a
    // page whose bundle is not loaded the mount is a fetch away - so cancelling at the mount both
    // misses the dispatches that fire during that fetch, against a registry that is still the
    // previous page's, and sweeps the ones the destination arms in the same window. Here nothing
    // of the destination exists yet, so every pending dispatch belongs to the page being left.
    Hologram.cancelScheduledActions();

    // The two halves of one rule, split at this instant: what was scheduled before the swap
    // belongs to the page being left and is dropped above, and what the destination's own script
    // dispatches after it is held below until the destination can answer for it. A swap starting
    // while another is still pending drops what the first destination held - that page never
    // mounted, so nothing will ever be able to answer for it.
    $.#isMountPending = true;
    $.#preMountActions = [];

    const pageModule = Interpreter.evaluateJavaScriptExpression(
      payload.pageModule,
    );

    const isPageModuleRegistered = $.#isPageModuleRegistered(pageModule);

    // The fetch is started before the patch, which is local work, so the network has a head start
    // on it. Nothing the bundle does can run before the patch is done, since it cannot execute
    // until this frame's work ends.
    if (!isPageModuleRegistered) {
      globalThis.Hologram.pageScriptLoaded = false;
      $.#loadPageBundle($.#pageBundlePath(payload.pageDigest));
    }

    const tree = Interpreter.evaluateJavaScriptExpression(payload.tree);
    const newVirtualDocument = Renderer.renderTree(tree);

    $.#dropPageBundleScript(newVirtualDocument, payload.pageDigest);

    Hologram.virtualDocument = Vdom.patchVirtualDocument(
      Hologram.virtualDocument,
      newVirtualDocument,
    );

    if (isPageModuleRegistered) {
      $.#mountPage(true);
    }
  }

  // Deps: [:maps.get/2, :maps.put/3]
  static #processActionResult(resultComponentStruct, name, target, startTime) {
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

    globalThis.Hologram.isProfilingEnabled = false;

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

      // A next action with no target of its own inherits the one that produced it, so it belongs
      // to the page being left - a navigation started below cancels it along with the rest.
      Hologram.scheduleAction(nextAction);
    }

    if (!Type.isNil(nextPage)) {
      $.#navigateToPage(nextPage);
    }
  }

  static #registerPageModule(pageModule) {
    $.#registeredPageModules.add(pageModule.value);
  }

  static async #restoreEts() {
    const storageKey = $.#ETS_STORAGE_KEY;

    // Try OPFS first
    try {
      const root = await navigator.storage.getDirectory();
      const fileHandle = await root.getFileHandle(storageKey, {create: false});
      const file = await fileHandle.getFile();
      const serialized = await file.text();
      ERTS.ets = Deserializer.deserialize(serialized);
      return;
    } catch {
      // Fall through to session storage
    }

    // Fallback to session storage if OPFS fails
    const serialized = sessionStorage.getItem(storageKey);

    if (serialized) {
      try {
        ERTS.ets = Deserializer.deserialize(serialized);
      } catch (error) {
        console.error("Failed to restore ETS from session storage:", error);
        ERTS.ets = {}; // Reset to empty on deserialization failure
      }
    } else {
      // No stored state found, keep current (likely empty) state
    }
  }

  static #restorePageSnapshot(pageSnapshot) {
    const {
      componentRegistryEntries,
      instanceId,
      pageModule,
      pageParams,
      scrollPosition,
      subscriptionReceipts,
    } = pageSnapshot;

    ComponentRegistry.populate(componentRegistryEntries);

    App.instanceId = instanceId;
    App.subscriptionReceiptRegistry.populate(subscriptionReceipts);

    Hologram.#pageModule = pageModule;
    Hologram.#pageParams = pageParams;

    $.#scrollPosition = scrollPosition;
    $.#shouldLoadMountData = false;
  }

  static async #saveEts() {
    const storageKey = $.#ETS_STORAGE_KEY;
    const serializedEts = Serializer.serialize(ERTS.ets, "client");

    // Save to session storage first (guaranteed to complete synchronously)
    try {
      sessionStorage.setItem(storageKey, serializedEts);
    } catch (error) {
      console.error("Failed to save ETS to session storage:", error);
    }

    // Then try OPFS (async, may not complete before page unload on beforeunload)
    try {
      const root = await navigator.storage.getDirectory();
      const fileHandle = await root.getFileHandle(storageKey, {create: true});
      const writable = await fileHandle.createWritable();
      await writable.write(serializedEts);
      await writable.close();

      // Successfully saved to OPFS, clear session storage
      sessionStorage.removeItem(storageKey);
    } catch (opfsError) {
      console.error("Failed to save ETS to OPFS:", opfsError);
      // Session storage still has the data as fallback
    }
  }

  static async #savePageSnapshot(forceSync = false) {
    const pageSnapshot = {
      componentRegistryEntries: ComponentRegistry.entries,
      instanceId: App.instanceId,
      pageModule: Hologram.#pageModule,
      pageParams: Hologram.#pageParams,
      scrollPosition: [window.scrollX, window.scrollY],
      subscriptionReceipts: Array.from(
        App.subscriptionReceiptRegistry.entries.entries(),
      ),
    };

    const snapshotKey = $.#pageSnapshotKey($.#historyId);

    // Always save deserialized object to in-memory cache first (fastest)
    $.#pageSnapshots.set(snapshotKey, pageSnapshot);

    const serializedPageSnapshot = Serializer.serialize(pageSnapshot, "client");

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

  static #scheduleHeldActions() {
    // The queue is emptied before anything runs, so each held action is released exactly once.
    const actions = $.#preMountActions;
    $.#preMountActions = [];

    actions.forEach((action) => {
      Hologram.scheduleAction(action);
    });
  }

  static #scheduleQueuedInitActions() {
    const actions = InitActionQueue.dequeueAll();

    actions.forEach((action) => {
      Hologram.scheduleAction(action);
    });
  }
}

const $ = Hologram;
