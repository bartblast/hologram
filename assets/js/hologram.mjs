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
  // The epoch of the page whose markup is on screen.
  static domEpoch = 0;

  // Made public to make tests easier
  // Whether a render is on the stack - its patch walking the live DOM, or its event bindings
  // being reconciled onto it. Set by render() alone: a patch made outside a render is not
  // covered, and has to keep a dispatch out by its own means.
  static isRendering = false;

  // Made public to make tests easier
  static prefetchedPages = new Map();

  // Made public to make tests easier
  // The epoch of the page the component registry answers for.
  static registryEpoch = 0;

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

  // Epochs whose navigation failed before it could mount - nothing can ever answer for them.
  static #deadEpochs = new Set();

  // Actions that arrived while a render was on the stack, waiting for it to finish.
  static #deferredActions = [];

  // Actions belonging to a page that cannot answer for them yet, waiting for its mount.
  static #heldActions = [];

  static #historyId = null;
  static #isInitiated = false;

  // A navigation's mount data, held between #showNewPage and the mount. The two are not always
  // adjacent: when the destination's code has not loaded yet the mount runs from the bundle's
  // announcement instead, so the state waits here rather than being passed along.
  static #mountData = null;

  static #pageModule = null;
  static #pageParams = null;
  static #pendingJsInteropActions = [];
  static #registeredPageModules = new Set();
  static #scrollPosition = null;
  static #shouldLoadMountData = true;

  // Public API for dispatching actions from JavaScript.
  // Converts plain JS values to Hologram types and schedules the action for execution.
  // Example: globalThis.Hologram.dispatchAction("increment", "page", {amount: 5})
  static dispatchAction(actionName, target, params = {}) {
    const action = Type.actionStruct({
      name: Type.atom(actionName),
      params: JsInterop.boxActionParam(params),
      target: Type.bitstring(target),
    });

    // Everything arriving here comes from script the page's own markup carries, so it belongs to
    // the page on screen - which during a transition is not yet the page the registry answers
    // for. The stamp is what lets it wait for that page's mount instead of resolving against the
    // page being left.
    Hologram.scheduleAction(action, $.domEpoch);
  }

  // This function is intentionally NOT async. Actions that use Task.await/1 return
  // a Promise, but we handle it with .then() instead of async/await. Making this
  // function async would wrap ALL errors (including from sync actions) in rejected
  // Promises, breaking ChromeDriver/Wallaby error detection which relies on the
  // synchronous "error" event. Async action errors are caught separately via the
  // "unhandledrejection" event listener in #init().
  // TODO: make private (tested implicitely in feature tests)
  // Deps: [:maps.get/2]
  static executeAction(action, epoch = $.registryEpoch) {
    const startTime = performance.now();
    globalThis.Hologram.isProfilingEnabled = true;

    const name = Erlang_Maps["get/2"](Type.atom("name"), action);
    const params = Erlang_Maps["get/2"](Type.atom("params"), action);
    const target = Erlang_Maps["get/2"](Type.atom("target"), action);

    // getComponentModule() answers with plain null for a cid the registry does not hold, and null
    // reaching callNamedFunction faults on reading a module name off it - a raw TypeError naming
    // neither the cid nor the action, which handleUncaughtError drops because it isn't boxed.
    // An action reaches here only through #settleAction, which admits it when its epoch is the
    // current one and the two epochs agree - so it was created while the registry answered for
    // the page it answers for now. A target that does not resolve is therefore a cid that page
    // never held, not a dispatch that outlived its own page - raised boxed, the way the error
    // overlay reads it.
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
        Hologram.#processActionResult(resolved, name, target, startTime, epoch),
      );
    } else {
      Hologram.#processActionResult(
        resultComponentStruct,
        name,
        target,
        startTime,
        epoch,
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

    // The dispatch below can run later than the event that caused it - a debounce or a throttle
    // holds it, and a navigation can start in between - so the page the user acted on is recorded
    // now, while it is still the page on screen.
    const epoch = $.domEpoch;

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

            // Settling directly keeps an undelayed dispatch synchronous on a stable page, which
            // is what lets a raising action reach the "error" event the feature tests read.
            if (delay.value === 0n) {
              return Hologram.#settleAction(operation, epoch);
            } else {
              return Hologram.scheduleAction(operation, epoch);
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

    // A synchronous DOM event can reach a dispatch from inside this render: removing the element
    // that has focus makes the browser fire focusout before the removal returns, and the document
    // listener flushes that element's pending debounced dispatches there and then. An action
    // running at that point renders into a tree this render is still walking, and the two renders
    // leave the DOM and the virtual document describing different pages. While this flag is set a
    // dispatch waits instead of running.
    $.isRendering = true;

    try {
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
    } finally {
      // A template expression is app code and can raise, so the flag is cleared on the way out
      // either way. Leaving it set would silence every dispatch from here on.
      $.isRendering = false;
    }

    console.log("Hologram: page rendered in", PerformanceTimer.diff(startTime));

    // Drained after the reconcile above rather than straight after the patch: a deferred action
    // renders, and a render collects the page's <window>/<document> bindings into
    // Renderer.listenerBindings. Running one earlier would leave this render reconciling the
    // other render's bindings.
    //
    // Reached only when the render finished. A render that raised left the DOM and the virtual
    // document describing different pages, and running the queue against that repairs nothing -
    // it waits for the next render that finishes.
    $.#drainDeferredActions();
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
  // The default stamp covers every caller that reasoned about the registry rather than about the
  // markup - server-pushed actions, command responses, and the queues the mount drains. A caller
  // whose action came from the DOM passes the displayed page's epoch instead.
  static scheduleAction(action, epoch = $.registryEpoch) {
    const delay = Erlang_Maps["get/3"](
      Type.atom("delay"),
      action,
      Type.integer(0),
    );

    setTimeout(() => {
      Hologram.#settleAction(action, epoch);
    }, Number(delay.value));
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

  // A document load leaves a shim that buffers whatever the page's script dispatches before the
  // runtime exists, since there is nothing yet to dispatch it to. The mount is the first moment
  // any of it can be answered, so that is where it drains. A dispatch made once the runtime is up
  // needs no buffer - it carries the epoch of the page that made it and waits on that instead.
  static #dispatchPendingJsInteropActions() {
    const actions = Hologram.#pendingJsInteropActions;
    Hologram.#pendingJsInteropActions = [];

    actions.forEach(([actionName, target, params]) => {
      Hologram.dispatchAction(actionName, target, params);
    });
  }

  // Runs what a render held back, in the order it arrived. Settled rather than executed: a
  // deferred action never got an answer from the settle rule, so it meets the same rules as any
  // other, against the page the client is on by the time it runs.
  //
  // One action is no reason to drop the rest: a single focusout flushes every pending slot on the
  // element at once, so a queue of several is the ordinary case, and they have nothing to do with
  // one another. Every one is delivered and the first error is raised once the queue is empty -
  // the same bargain the debouncer makes with the callbacks it flushes.
  static #drainDeferredActions() {
    let firstError;

    while ($.#deferredActions.length > 0) {
      const {action, epoch} = $.#deferredActions.shift();

      try {
        $.#settleAction(action, epoch);
      } catch (error) {
        firstError ??= error;
      }
    }

    if (firstError !== undefined) {
      throw firstError;
    }
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
    // The same boundary as #showNewPage, on the history's side of it: nothing of the destination
    // exists yet, so every debounced or throttled dispatch still pending belongs to the page being
    // left. It cannot wait for the restore below, which a popstate carrying no snapshot skips.
    Debouncer.cancelAll();
    Throttler.cancelAll();

    await $.#savePageSnapshot();
    $.#historyId = event.state;

    const pageSnapshot = await $.#getPageSnapshot(event.state);

    if (pageSnapshot) {
      $.#restorePageSnapshot(pageSnapshot);
    } else {
      // With no snapshot to restore, the mount below reads the document's mount data instead and
      // repopulates the registry from it, putting every component back to the state it was
      // rendered with. That is as much a change of what the registry answers for as a restore is,
      // so it advances the same way - otherwise an action armed before this point would settle
      // against state that has been reset underneath it.
      $.registryEpoch = Math.max($.domEpoch, $.registryEpoch) + 1;
    }

    if ($.#isPageModuleRegistered(Hologram.#pageModule)) {
      return $.#mountPage(true);
    }

    // The epoch of the navigation this restore opened. The fetch below is a round trip, and a
    // later navigation may supersede this one before it answers - the failure of a superseded
    // fetch says nothing about the navigation now in flight.
    const epoch = Math.max($.domEpoch, $.registryEpoch);

    await Client.fetchPageBundlePath(
      Hologram.#pageModule,
      (resp) => $.#loadPageBundle(resp, epoch),
      (_resp) => {
        // The mount that would have closed this transition is never going to run.
        $.#deadEpochs.add(epoch);

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
  // A navigation carries the mount data as payload fields, which #showNewPage decodes and holds.
  // A loaded document has no payload, so it carries the same six values as an inline script that
  // defines pageMountData - the one channel markup has for structured state.
  static #loadMountData() {
    const mountData =
      $.#mountData ?? globalThis.Hologram.pageMountData(Hologram.#deps);

    $.#mountData = null;

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
  // The epoch defaults to an at-call capture, which is right for the forward path, where the
  // call follows the transition's epoch advance synchronously. The popstate path reaches here a
  // round trip after its advance and passes the epoch it captured before that trip - a later
  // navigation may have started in between, and the failure of a superseded fetch says nothing
  // about the navigation now in flight.
  static #loadPageBundle(src, epoch = Math.max($.domEpoch, $.registryEpoch)) {
    const script = document.createElement("script");

    script.src = src;
    script.fetchpriority = "high";

    script.onerror = () => {
      // The mount that would have released this epoch's held dispatches is never going to run.
      $.#deadEpochs.add(epoch);

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
    // Nothing pending from the page the user left is dropped here. It is dropped at the instant
    // the user leaves instead - in #showNewPage and #handlePopstateEvent - which is the last
    // point at which every pending timer provably belongs to the page being left.
    //
    // Whichever pointer ran ahead during the transition, the mount is where they converge: from
    // here the page on screen and the page the registry answers for are the same page.
    $.domEpoch = $.registryEpoch = Math.max($.domEpoch, $.registryEpoch);

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
      // The registry arrives with every struct's props empty - this render is what writes them, so
      // that the payload doesn't carry each prop value a second time - which is one more reason
      // nothing above may run a handler before this call, and why every drain below it stays below
      // it.
      $.render();

      if ($.#scrollPosition) {
        window.scrollTo($.#scrollPosition[0], $.#scrollPosition[1]);
        $.#scrollPosition = null;
      }

      GlobalRegistry.set("mountedPage", Interpreter.inspect($.#pageModule));

      Hologram.#scheduleQueuedInitActions();
      Hologram.#dispatchPendingJsInteropActions();
      Hologram.#releaseHeldActions();
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
    // What an earlier page buffered and never got to dispatch belongs to that page, and that
    // page is being left too. The buffer predates stamping - a document load fills it before the
    // runtime exists - so it is the one queue the epoch cannot speak for, and it is emptied by
    // hand.
    $.#pendingJsInteropActions = [];

    // A debounce or a throttle holds its dispatch in a timer rather than in a queue, and a timer
    // outlives the page that armed it. This line is the last instant that is still only the page
    // being left - nothing of the destination is on screen, none of its listeners are attached,
    // none of its scripts have run - so every timer pending here provably belongs to the page
    // being left, and cancelling all of them takes nothing from the destination. Cancel, not
    // flush: a dispatch must never execute on a page the user has left.
    Debouncer.cancelAll();
    Throttler.cancelAll();

    // The patch below puts the destination's markup on screen and runs its scripts, so the epoch
    // of what is displayed advances here, ahead of the registry - the mount brings the registry
    // level. What the destination's script dispatches from here on carries that epoch and waits
    // for the mount, while everything armed before this line belongs to the page being left.
    $.domEpoch = Math.max($.domEpoch, $.registryEpoch) + 1;

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

    // Readable before the patch, rather than as a side effect of a script the patch inserts and
    // the browser then runs. The page module is already decoded above, so it is reused.
    $.#mountData = {
      componentRegistry: Interpreter.evaluateJavaScriptExpression(
        payload.componentRegistry,
      ),
      pageModule: pageModule,
      pageParams: Interpreter.evaluateJavaScriptExpression(payload.pageParams),
      selfEchoes: Interpreter.evaluateJavaScriptExpression(payload.selfEchoes),
      subReceiptAdds: Interpreter.evaluateJavaScriptExpression(
        payload.subReceiptAdds,
      ),
      subReceiptDrops: Interpreter.evaluateJavaScriptExpression(
        payload.subReceiptDrops,
      ),
    };

    // See: docs/navigation_payload_wire_format.md
    const tree = Renderer.decodeTree(payload.tree);
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
  static #processActionResult(
    resultComponentStruct,
    name,
    target,
    startTime,
    epoch,
  ) {
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

      // A next action belongs to whatever page its parent belonged to, so it inherits the
      // parent's stamp rather than reading the epoch afresh. That matters most when the parent
      // was asynchronous: its promise can resolve after a navigation, and the inherited stamp is
      // what makes the next action drop instead of landing on a page that never produced it.
      Hologram.scheduleAction(nextAction, epoch);
    }

    if (!Type.isNil(nextPage)) {
      $.#navigateToPage(nextPage);
    }
  }

  static #registerPageModule(pageModule) {
    $.#registeredPageModules.add(pageModule.value);
  }

  static #releaseHeldActions() {
    const held = $.#heldActions;
    $.#heldActions = [];

    for (const {action, epoch} of held) {
      // An entry from a transition that never reached this mount belongs to a page that will
      // never answer for it.
      if (epoch !== $.registryEpoch) {
        continue;
      }

      // A held action already served its own delay before it was held - the timer is what
      // delivered it to the settle rule in the first place - so releasing it goes through a bare
      // macrotask rather than scheduleAction, which would serve that delay a second time. The
      // macrotask is not incidental: it puts the release behind the init-action and JS-interop
      // drains, which ride timers of their own, and keeps a raising action surfacing the way
      // every other timer-driven action does.
      setTimeout(() => {
        Hologram.#settleAction(action, epoch);
      }, 0);
    }
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

    // A restore swaps the registry while the previous page is still on screen - the mirror of a
    // forward navigation, where the markup runs ahead instead. The epoch of what the registry
    // answers for advances here; the mount brings the displayed side level.
    $.registryEpoch = Math.max($.domEpoch, $.registryEpoch) + 1;

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

  static #scheduleQueuedInitActions() {
    const actions = InitActionQueue.dequeueAll();

    actions.forEach((action) => {
      Hologram.scheduleAction(action);
    });
  }

  // The one place an action meets the registry, and the only thing that decides whether it runs.
  // An action carries the epoch of the page it was reasoning about when it was created, and this
  // compares that against where the client has got to since.
  static #settleAction(action, epoch) {
    const currentEpoch = Math.max($.domEpoch, $.registryEpoch);

    // The page the action belonged to has been left, or its navigation failed before it could
    // mount - either way nothing can answer for it any more. The warning is the trace a button
    // that appears to do nothing leaves behind.
    if (epoch < currentEpoch || $.#deadEpochs.has(epoch)) {
      console.warn(
        "Hologram: dropped an action dispatched on a page that has been left:",
        Interpreter.inspect(Erlang_Maps["get/2"](Type.atom("name"), action)),
      );

      return;
    }

    // The two sides disagree, so the client is mid-transition: the page this action belongs to is
    // the one being moved to, and it cannot answer until it mounts.
    if ($.domEpoch !== $.registryEpoch) {
      $.#heldActions.push({action: action, epoch: epoch});
      return;
    }

    // A render is on the stack, so the DOM it is walking is mid-update and this action's own
    // render would walk the same tree behind it. It waits, and runs when that render is done.
    if ($.isRendering) {
      $.#deferredActions.push({action: action, epoch: epoch});
      return;
    }

    return Hologram.executeAction(action, epoch);
  }
}

const $ = Hologram;
