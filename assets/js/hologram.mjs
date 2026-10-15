"use strict";

import ActionQueue from "./action_queue.mjs";
import App from "./app.mjs";
import AssetPathRegistry from "./asset_path_registry.mjs";
import Batches from "./batches.mjs";
import Bitstring from "./bitstring.mjs";
import Client from "./client.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Debouncer from "./debouncer.mjs";
import Deltas from "./deltas.mjs";
import Deserializer from "./deserializer.mjs";
import Dispatch from "./dispatch.mjs";
import Durability from "./durability.mjs";
import ERTS from "./erts.mjs";
import EventListenerRegistry from "./event_listener_registry.mjs";
import EventListeners from "./event_listeners.mjs";
import GlobalRegistry from "./global_registry.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import JsInterop from "./js_interop.mjs";
import LiveReload from "./live_reload.mjs";
import LocalDatabase from "./local_database.mjs";
import MemoryStorage from "./memory_storage.mjs";
import MountGate from "./mount_gate.mjs";
import PerformanceTimer from "./performance_timer.mjs";
import Renderer from "./renderer.mjs";
import Replica from "./replica.mjs";
import ScriptRegistry from "./script_registry.mjs";
import Serializer from "./serializer.mjs";
import Sse from "./sse.mjs";
import SyncStream from "./sync_stream.mjs";
import Tabs from "./tabs.mjs";
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
import ManuallyPortedElixirHologramAuth from "./elixir/hologram/auth.mjs";
import ManuallyPortedElixirHologramDB from "./elixir/hologram/db.mjs";
import ManuallyPortedElixirHologramEntity from "./elixir/hologram/entity.mjs";
import ManuallyPortedElixirHologramJS from "./elixir/hologram/js.mjs";
import ManuallyPortedElixirHologramJob from "./elixir/hologram/job.mjs";
import ManuallyPortedElixirHologramQuery from "./elixir/hologram/query.mjs";
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
  // True from the start of a mount to the end of its first render. The registry arrives with every
  // struct's props empty and that render is what writes them, so no action may run before it. Set
  // and cleared by #mountPage.
  static isMounting = false;

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

  // Component ids whose action is running asynchronously, each with the epoch of the page it
  // belongs to, from the action's start to the commit of its result. The queue waits for it on
  // that component only: the next action for the component reads its state, and the state it must
  // read is the one the running action is about to write. Other components' actions are not held -
  // an action never writes another component's struct, so there is nothing for them to wait for.
  // Emptied when the page is left: what was awaiting belongs to the page being left, and the
  // destination may hold the same cids.
  static #awaitingTargets = new Map();

  // The digests of the chunks this document was told of: the ones the document the server sent
  // carries and the ones requested since. A snapshot saves the loaded ones.
  static #chunkDigests = new Set();

  // Epochs whose navigation failed before it could mount - nothing can ever answer for them.
  static #deadEpochs = new Set();

  // The snapshot of the history entry this document was loaded for, found while the runtime was
  // starting and restored by run() once its chunks are in. Null when there is none to restore, and
  // once that is settled.
  static #documentSnapshot = null;

  static #historyId = null;
  static #isInitiated = false;

  // True while #runActions walks the queue. A running action can enqueue another one synchronously
  // (an event its own code fires on the DOM, a debounce flush), and that one is picked up by the
  // walk already on the stack rather than by a nested one, which would run it in the middle of its
  // parent.
  static #isRunningActions = false;

  // A navigation's mount data, held between #showNewPage and the mount. The two are not always
  // adjacent: when the destination's code has not loaded yet the mount runs from the bundle's
  // announcement instead, so the state waits here rather than being passed along.
  static #mountData = null;

  static #pageModule = null;
  static #pageParams = null;
  static #pendingJsInteropActions = [];
  static #registeredPageModules = new Set();

  // For each snapshot restore in flight, the chunks it waits for (see #loadSnapshotChunks).
  static #restoresInFlight = new Set();

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

  // Puts an action on the queue and runs the queue: a DOM event's dispatch, a timer scheduleAction
  // set, a command's reply, a server push. A mount and a render put their own actions on the queue
  // directly, through enqueueActionAfterDelay, since they run it themselves once they are done. An
  // action carries the epoch of the page it was reasoning about when it was created, and
  // #runActions compares that against where the client has got to by the time the action reaches
  // the head of the queue.
  static enqueueAction(action, epoch = $.registryEpoch) {
    ActionQueue.enqueue(action, epoch);
    Hologram.#runActions();
  }

  // Puts an action the mount or a render brings on the queue: at once, or once its delay has
  // elapsed, like any delayed action. The queue is not run here - the mount and the render run it
  // themselves once they are done, and a delayed one enters through scheduleAction's timer, which
  // runs it.
  // Deps: [:maps.get/3]
  static enqueueActionAfterDelay(action, epoch = $.registryEpoch) {
    const delay = Erlang_Maps["get/3"](
      Type.atom("delay"),
      action,
      Type.integer(0),
    );

    if (delay.value === 0n) {
      ActionQueue.enqueue(action, epoch);
    } else {
      Hologram.scheduleAction(action, epoch);
    }
  }

  // This function is intentionally NOT async. Actions that use Task.await/1 return
  // a Promise, but we handle it with .then() instead of async/await. Making this
  // function async would wrap ALL errors (including from sync actions) in rejected
  // Promises, breaking ChromeDriver/Wallaby error detection which relies on the
  // synchronous "error" event. Async action errors are caught separately via the
  // "unhandledrejection" event listener in #init().
  //
  // Returns the promise of an asynchronous action, settled once its result has been processed, so
  // that a caller can wait for the commit. A synchronous action returns nothing.
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
    // An action reaches here only through #runActions, which runs it when its epoch is the
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

    // An action's writes are one batch: opened here, sealed when it returns, discarded when it
    // raises. That is what makes "the writes of one action" need no bookkeeping from the app - a
    // DB verb writes to whichever batch is open, and there is one open only while an action runs.
    Batches.open(target);

    let resultComponentStruct;

    try {
      resultComponentStruct = Interpreter.callNamedFunction(
        componentModule,
        Type.atom("action"),
        Type.list(args),
        context,
      );
    } catch (error) {
      // Nothing half-done: an action that raises leaves no rows behind, and dropping the batch is
      // the whole of putting them back. The error goes on to handleUncaughtError as it always did.
      Batches.discard();

      throw error;
    }

    if (resultComponentStruct instanceof Promise) {
      return resultComponentStruct.then(
        (resolved) =>
          Hologram.#processActionResult(
            resolved,
            name,
            target,
            startTime,
            epoch,
          ),
        (error) => {
          Batches.discard();

          throw error;
        },
      );
    }

    Hologram.#processActionResult(
      resultComponentStruct,
      name,
      target,
      startTime,
      epoch,
    );
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
      Hologram.navigateBrowserTo(pagePath);
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
      Hologram.navigateBrowserTo(mapValue.pagePath);
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
    dispatchSpecDom,
    defaultTarget,
    allowDefault = false,
    stopPropagation = false,
    forcePreventDefault = false,
  ) {
    // The guard runs before preventDefault and stopPropagation, so a disabled binding leaves
    // native browser behavior fully untouched.
    if (Dispatch.isDisabled(dispatchSpecDom)) {
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

    const eventParam = eventImpl.buildEventParam(event);
    const eventTarget = event.target;

    // The dispatch below can run later than the event that caused it - a debounce or a throttle
    // holds it, and a navigation can start in between - so the page the user acted on is recorded
    // now, while it is still the page on screen.
    const epoch = $.domEpoch;

    return () => {
      const dispatch = Dispatch.fromSpecDom(
        dispatchSpecDom,
        defaultTarget,
        eventParam,
      );

      if (Dispatch.isAction(dispatch)) {
        switch (Hologram.#getActionName(dispatch)) {
          case "__load_prefetched_page__":
            return Hologram.executeLoadPrefetchedPageAction(
              dispatch,
              eventTarget,
            );

          case "__prefetch_page__":
            return Hologram.executePrefetchPageAction(dispatch, eventTarget);

          default: {
            const delay = Erlang_Maps["get/3"](
              Type.atom("delay"),
              dispatch,
              Type.integer(0),
            );

            // Enqueuing directly keeps an undelayed dispatch synchronous on a stable page - an
            // idle queue runs it at once - which is what lets a raising action reach the "error"
            // event the feature tests read.
            if (delay.value === 0n) {
              return Hologram.enqueueAction(dispatch, epoch);
            } else {
              return Hologram.scheduleAction(dispatch, epoch);
            }
          }
        }
      } else {
        Client.sendCommand(dispatch);
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
  // Takes the page the server described, or where it says to go instead. A redirect is followed by
  // asking for the page it names, so only the page actually arrived at is mounted and only its path
  // enters history - the same trail a browser leaves, where the pages passed through on the way are
  // not places the user can go back to.
  //
  // The page goes into a new history entry, unless the id of an entry is given: that entry exists
  // already (the browser went back or forward to it) and the page is shown in its place.
  static async loadNewPage(
    pagePath,
    payload,
    hopCount = 0,
    historyEntryId = null,
  ) {
    if (payload.type === "redirect") {
      return Hologram.#followRedirect(payload, hopCount, historyEntryId);
    }

    const pageModule = Interpreter.evaluateJavaScriptExpression(
      payload.pageModule,
    );

    // The tab holds this page's code from an earlier visit, and a live reload has rebuilt it since.
    // Running the held copy would show the page as it was before the edit, so the browser loads
    // the page afresh instead.
    if (LiveReload.holdsOldPageBundle(pageModule, payload.pageDigest)) {
      $.#handToBrowser(pagePath, historyEntryId);
      return;
    }

    if (historyEntryId === null) {
      await $.#savePageSnapshot();
      $.#historyId = Utils.uuidv7();
    } else {
      // The page being left was saved when the browser left its entry. From here on the tab
      // answers for this one.
      $.#historyId = historyEntryId;
    }

    window.requestAnimationFrame(() => {
      Hologram.#showNewPage(payload);
      window.scrollTo(0, 0);

      if (historyEntryId === null) {
        history.pushState($.#historyId, null, pagePath);
      } else {
        // A redirect can have led to another path than the one the entry held.
        history.replaceState($.#historyId, null, pagePath);
      }
    });
  }

  // Made public to make tests easier
  //
  // Hands the navigation to the browser instead of doing it in the app, which is how Hologram answers
  // anything it does not mount itself: a target outside the app, or a response a page's middleware
  // wrote itself. The browser then gets the same answer a typed-in URL would have got, address bar
  // and history included: the document is loaded afresh and a history entry is added.
  static navigateBrowserTo(url) {
    window.location.assign(url);
  }

  // The module of the page this tab shows, as the last mount or restore set it.
  static pageModule() {
    return Hologram.#pageModule;
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

        Hologram.enqueueActionAfterDelay(actionWithTarget, $.registryEpoch);
      }
    }
  }

  // Made public to make tests easier
  static queueSelfEchoes(selfEchoes) {
    for (const action of selfEchoes.data) {
      Hologram.enqueueActionAfterDelay(action, $.registryEpoch);
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
      // has fired, so reconcile tears it down. A navigation has already detached the previous
      // page's listeners at its boundary, so a mount's reconcile attaches against an empty
      // registry: every mount attaches fresh, and no listener's private state crosses from one
      // page to the next.
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

    // Run after the reconcile above rather than straight after the patch: a waiting action
    // renders, and a render collects the page's <window>/<document> bindings into
    // Renderer.listenerBindings. Running one earlier would leave this render reconciling the
    // other render's bindings.
    //
    // Reached only when the render finished. A render that raised left the DOM and the virtual
    // document describing different pages, and running the queue against that repairs nothing -
    // it waits for the next render that finishes.
    Hologram.#runActions();
  }

  // Made public to make tests easier
  //
  // Hands the navigation to the browser like navigateBrowserTo() does, for a page that was being
  // loaded into the history entry the tab is on: the document is loaded afresh in that entry, and
  // none is added.
  static replaceBrowserLocation(url) {
    window.location.replace(url);
  }

  // Fetches the chunks with the given digests, unless the document has them (see ScriptRegistry).
  // A chunk holds code of struct types that no bundle carries, their struct functions and their
  // protocol implementations, and is named when a value of such a type, or the type's module, is
  // on its way to the browser.
  static requestChunks(digests) {
    digests.forEach((digest) => $.#chunkDigests.add(digest));

    ScriptRegistry.request(
      digests.map((digest) => ({
        digest: digest,
        path: $.#chunkBundlePath(digest),
      })),
      (digest) => $.#handleScriptFailure(digest),
    );
  }

  static run() {
    Hologram.#onReady(async () => {
      if (!Hologram.#isInitiated) {
        await Hologram.#init();
      }

      // The document's own page bundle and chunks are what its mount waits for. Their script
      // elements are in the document the server sent, so they are not requested here.
      MountGate.require($.#initialScriptDigests());

      // A snapshot can need more chunks than the server rendered the page with. It is restored
      // once they are in. When one cannot be had the snapshot is passed over, and the page mounts
      // from the state the server has just rendered, which the document carries.
      const pageSnapshot = $.#documentSnapshot;

      const isRestorable =
        pageSnapshot !== null && (await $.#loadSnapshotChunks(pageSnapshot));

      $.#documentSnapshot = null;

      if (isRestorable) {
        $.registryEpoch = Math.max($.domEpoch, $.registryEpoch) + 1;
        $.#restorePageSnapshot(pageSnapshot);

        // The mount after a restore reads no mount data, which is where a page's bundle digest is
        // recorded, so this document's is recorded here: the snapshot it saves on leaving is
        // stamped with it.
        LiveReload.recordPageBundle(
          pageSnapshot.pageModule,
          globalThis.Hologram.initialPageDigest,
        );
      }

      Hologram.#mountWhenReady(false);
    });
  }

  // Runs the action once its delay has elapsed. The timer's callback is a new task, so the browser
  // can paint before the action runs, with no delay too.
  // Deps: [:maps.get/3]
  // The default stamp covers every caller that reasoned about the registry rather than about the
  // markup - server-pushed actions and command responses. A caller whose action came from the DOM
  // passes the displayed page's epoch instead.
  static scheduleAction(action, epoch = $.registryEpoch) {
    const delay = Erlang_Maps["get/3"](
      Type.atom("delay"),
      action,
      Type.integer(0),
    );

    setTimeout(() => {
      Hologram.enqueueAction(action, epoch);
    }, Number(delay.value));
  }

  // Schedules an action the server pushed: a command reply's next action or self echo, or an action
  // or a broadcast that came over SSE. Such an action can carry a value of a struct type, or the
  // type's module, whose struct functions and protocol implementations the tab has not loaded, and
  // must not run before the chunks that hold them are in. The server names those chunks, by digest.
  //
  // The wait happens here, before the action queue, since an action still waiting for its chunks
  // has not arrived as far as the page is concerned: nothing the user does queues up behind it.
  // An action triggered on the client never waits, because the state only ever holds values whose
  // chunks the tab has.
  //
  // Realtime promises no order, so two pushed actions can run in the other order than the one
  // they were sent in, when the first of them waits for a chunk.
  // Deps: [:maps.get/2]
  static schedulePushedAction(action, chunkDigests) {
    // Captured on arrival: a navigation while the chunks are fetched must leave the action stamped
    // with the page it was sent to, so that the queue drops it as stale.
    const epoch = $.registryEpoch;

    $.requestChunks(chunkDigests);

    if (ScriptRegistry.isLoaded(chunkDigests)) {
      $.scheduleAction(action, epoch);
      return;
    }

    ScriptRegistry.whenLoaded(chunkDigests).then(
      () => $.scheduleAction(action, epoch),
      (digest) => {
        console.warn(
          "Hologram: dropped a pushed action whose chunk failed to load:",
          Interpreter.inspect(Erlang_Maps["get/2"](Type.atom("name"), action)),
          digest,
        );
      },
    );
  }

  static #buildPagePath(toParam) {
    return Bitstring.toText(
      Elixir_Hologram_Router_Helpers["page_path/1"](toParam),
    );
  }

  static #buildPrefetchedPagesMapKey(eventTargetNode, pagePath) {
    return `${eventTargetNode.__hologramId__}:${pagePath}`;
  }

  // Mirrors Hologram.Router.Helpers.chunk_bundle_path/1
  static #chunkBundlePath(chunkDigest) {
    return `/hologram/chunk-${chunkDigest}.js`;
  }

  // Defines the functions of the scripts that announced themselves (see ScriptRegistry), and lets
  // the waiting mount through when they were the last ones it waited for.
  static #defineLoadedScripts() {
    ScriptRegistry.defineLoaded(Hologram.#deps);
    MountGate.settle();
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
      "Hologram.Auth",
      "can?/3",
      "public",
      ManuallyPortedElixirHologramAuth["can?/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "grant_role/2",
      "public",
      ManuallyPortedElixirHologramAuth["grant_role/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "grant_role/3",
      "public",
      ManuallyPortedElixirHologramAuth["grant_role/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "revoke_role/2",
      "public",
      ManuallyPortedElixirHologramAuth["revoke_role/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "revoke_role/3",
      "public",
      ManuallyPortedElixirHologramAuth["revoke_role/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "create!/1",
      "public",
      ManuallyPortedElixirHologramDB["create!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "create/1",
      "public",
      ManuallyPortedElixirHologramDB["create/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete!/1",
      "public",
      ManuallyPortedElixirHologramDB["delete!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete!/2",
      "public",
      ManuallyPortedElixirHologramDB["delete!/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete/1",
      "public",
      ManuallyPortedElixirHologramDB["delete/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete/2",
      "public",
      ManuallyPortedElixirHologramDB["delete/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "read/1",
      "public",
      ManuallyPortedElixirHologramDB["read/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "read/2",
      "public",
      ManuallyPortedElixirHologramDB["read/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "rollback/1",
      "public",
      ManuallyPortedElixirHologramDB["rollback/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "transaction/1",
      "public",
      ManuallyPortedElixirHologramDB["transaction/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "transaction/2",
      "public",
      ManuallyPortedElixirHologramDB["transaction/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update!/1",
      "public",
      ManuallyPortedElixirHologramDB["update!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update!/3",
      "public",
      ManuallyPortedElixirHologramDB["update!/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update/1",
      "public",
      ManuallyPortedElixirHologramDB["update/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update/3",
      "public",
      ManuallyPortedElixirHologramDB["update/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "generate_id/0",
      "public",
      ManuallyPortedElixirHologramEntity["generate_id/0"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "new/1",
      "public",
      ManuallyPortedElixirHologramEntity["new/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "new/2",
      "public",
      ManuallyPortedElixirHologramEntity["new/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "validate/1",
      "public",
      ManuallyPortedElixirHologramEntity["validate/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "validate/2",
      "public",
      ManuallyPortedElixirHologramEntity["validate/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "add_relationship/3",
      "public",
      ManuallyPortedElixirHologramQuery["add_relationship/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "authorize/2",
      "public",
      ManuallyPortedElixirHologramQuery["authorize/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "count/1",
      "public",
      ManuallyPortedElixirHologramQuery["count/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "decrement/3",
      "public",
      ManuallyPortedElixirHologramQuery["decrement/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "delete_relationship/3",
      "public",
      ManuallyPortedElixirHologramQuery["delete_relationship/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "filter/2",
      "public",
      ManuallyPortedElixirHologramQuery["filter/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "include/2",
      "public",
      ManuallyPortedElixirHologramQuery["include/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "include/3",
      "public",
      ManuallyPortedElixirHologramQuery["include/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "increment/3",
      "public",
      ManuallyPortedElixirHologramQuery["increment/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "limit/2",
      "public",
      ManuallyPortedElixirHologramQuery["limit/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "normalize/1",
      "public",
      ManuallyPortedElixirHologramQuery["normalize/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "offset/2",
      "public",
      ManuallyPortedElixirHologramQuery["offset/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "one/1",
      "public",
      ManuallyPortedElixirHologramQuery["one/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "order_by/2",
      "public",
      ManuallyPortedElixirHologramQuery["order_by/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "put_attribute/2",
      "public",
      ManuallyPortedElixirHologramQuery["put_attribute/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "put_attribute/3",
      "public",
      ManuallyPortedElixirHologramQuery["put_attribute/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query",
      "trust/1",
      "public",
      ManuallyPortedElixirHologramQuery["trust/1"],
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
      "Hologram.Job",
      "create!/1",
      "public",
      ManuallyPortedElixirHologramJob["create!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create!/2",
      "public",
      ManuallyPortedElixirHologramJob["create!/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create!/3",
      "public",
      ManuallyPortedElixirHologramJob["create!/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create/1",
      "public",
      ManuallyPortedElixirHologramJob["create/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create/2",
      "public",
      ManuallyPortedElixirHologramJob["create/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create/3",
      "public",
      ManuallyPortedElixirHologramJob["create/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "framework_attribute_names/0",
      "public",
      ManuallyPortedElixirHologramJob["framework_attribute_names/0"],
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

  // Everything the page being left armed is dropped at the boundary: a debounce or throttle
  // timer, and every registry listener - a <window>/<document> binding, a click_outside, a reach
  // or resize observer. A timer outlives the page that armed it, and a listener attached to a
  // target the patch does not own would observe the patch itself: a detached element's observer
  // reports it at 0x0, a shortened document fires the scroll the browser clamps, and every such
  // dispatch would carry the destination's epoch. Nothing of the destination exists yet at
  // either boundary, so nothing of it is taken, and the mount's render attaches its listeners
  // afresh. Cancel, not flush: a dispatch must never execute on a page the user has left.
  static #disarmLeftPage() {
    Debouncer.cancelAll();
    Throttler.cancelAll();
    EventListenerRegistry.detachAll();
  }

  // What the document the server sent mounts with: the values its boot script defines, and the
  // digest of the page's bundle, which the boot script sets beside them. Read by whichever comes
  // first, the tab group's naming or the mount, since both need it and the second takes what the
  // first read.
  static #documentMountData() {
    return {
      ...globalThis.Hologram.pageMountData(Hologram.#deps),
      pageDigest: globalThis.Hologram.initialPageDigest,
    };
  }

  // Takes the page's own bundle out of the document the server described, leaving every other
  // script it carries to be patched in and run.
  //
  // The bundle is fetched here rather than through the patch so that a failure to load is
  // noticed - ScriptRegistry gives it a failure path, which a script the patch creates would
  // not have. It also settles what a script element cannot express on its own: a script is keyed
  // by the source it loads, so navigating back to a page whose bundle is already in the document
  // would adopt that element and never run it, while navigating to a page whose bundle is in
  // memory but absent from the document would run it a second time.
  //
  // The document is the one just built from the tree, so it is edited in place.
  static #dropPageBundleScript(virtualDocument, pageModule, pageDigest) {
    const key = `__hologramScript__:${$.#pageBundlePath(pageModule, pageDigest)}`;

    const headVnode = virtualDocument.children.find(
      (childVnode) => childVnode?.sel === "head",
    );

    if (headVnode) {
      headVnode.children = headVnode.children.filter(
        (childVnode) => childVnode?.key !== key,
      );
    }
  }

  // A document load leaves a shim that buffers whatever the page's script dispatches before the
  // runtime exists, since there is nothing yet to dispatch it to. The mount is the first moment
  // any of it can be answered, so that is where it enters the queue, stamped with the mount's
  // page. A dispatch made once the runtime is up needs no buffer - it carries the epoch of the
  // page that made it and waits on that instead.
  static #enqueuePendingJsInteropActions() {
    const actions = Hologram.#pendingJsInteropActions;
    Hologram.#pendingJsInteropActions = [];

    actions.forEach(([actionName, target, params]) => {
      const action = Type.actionStruct({
        name: Type.atom(actionName),
        params: JsInterop.boxActionParam(params),
        target: Type.bitstring(target),
      });

      ActionQueue.enqueue(action, $.registryEpoch);
    });
  }

  static #ensureDomNodeHasHologramId(eventNode) {
    if (typeof eventNode.__hologramId__ === "undefined") {
      eventNode.__hologramId__ = Utils.uuidv7();
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
  static #getToParam(dispatch) {
    return Erlang_Maps["get/2"](
      Type.atom("to"),
      Erlang_Maps["get/2"](Type.atom("params"), dispatch),
    );
  }

  // Made public to make tests easier
  static async handlePopstateEvent(event) {
    // The same boundary as #showNewPage, on the history's side of it. It cannot wait for the
    // restore below, which a popstate carrying no snapshot skips.
    $.#disarmLeftPage();

    // What was awaiting belongs to the page being left, and the destination may hold the same
    // cids. Emptied here for the same reason the timers are cancelled here.
    $.#awaitingTargets.clear();

    await $.#savePageSnapshot();

    const pageSnapshot = await $.#getPageSnapshot(event.state);

    // Asked before anything of the page being left is given up: where live reload runs, this is a
    // round trip to the server.
    const isSnapshotOutdated = pageSnapshot
      ? await $.#isSnapshotOutdated(pageSnapshot)
      : false;

    // What the registry answers for is about to change either way: a restore swaps it for the
    // snapshot's, a snapshot that cannot be restored gives way to the page the server renders, and
    // with no snapshot the mount reads the document's mount data instead and repopulates the
    // registry from it, putting every component back to the state it was rendered with. So the
    // epoch advances here - otherwise an action armed before this point would settle against
    // state that has been replaced underneath it.
    $.registryEpoch = Math.max($.domEpoch, $.registryEpoch) + 1;

    // The epoch of the navigation this popstate opened. What follows waits, for the snapshot's
    // chunks and for the server, and a later navigation may supersede this one before either
    // answers - neither the answer nor the failure of a superseded wait says anything about the
    // navigation now in flight.
    const epoch = $.registryEpoch;
    const isSuperseded = () => Math.max($.domEpoch, $.registryEpoch) !== epoch;

    // The history id stays the page being left's until the registry holds the page of the entry
    // the browser went to: a snapshot saved meanwhile is of the page still on screen, and belongs
    // under that page's entry.
    const historyEntryId = event.state;

    // A snapshot taken with code other than the page's current one is not restored.
    if (isSnapshotOutdated) {
      return $.#loadHistoryEntryPage(historyEntryId, pageSnapshot, epoch);
    }

    if (!pageSnapshot) {
      $.#historyId = historyEntryId;
    }

    // The page on its way: the snapshot's, or with none the one the tab already answers for.
    const pageModule = pageSnapshot
      ? pageSnapshot.pageModule
      : Hologram.#pageModule;

    let snapshotChunksLoaded = null;

    if (pageSnapshot) {
      // A mount still waiting belongs to a navigation this one supersedes, and nothing is put in
      // its place until the snapshot's chunks are in.
      MountGate.cancel();
      MountGate.require([]);

      // Asked for now, so that they load while the server is asked for the page's bundle.
      snapshotChunksLoaded = $.#loadSnapshotChunks(pageSnapshot);
    }

    // Closes the transition. A snapshot is restored only once its chunks are in, so that one that
    // cannot be restored leaves the tab as it was, and the entry's page is asked for instead.
    const mount = async (isPageModuleRegistered, pageBundleDigests) => {
      if (pageSnapshot) {
        const loaded = await snapshotChunksLoaded;

        // A later navigation took over meanwhile, or the page's bundle failed to load, which ended
        // this navigation already.
        if (isSuperseded() || ScriptRegistry.hasFailed(pageBundleDigests)) {
          return;
        }

        if (!loaded) {
          return $.#loadHistoryEntryPage(historyEntryId, pageSnapshot, epoch);
        }

        $.#historyId = historyEntryId;
        $.#restorePageSnapshot(pageSnapshot);
      }

      $.#mountWhenReady(isPageModuleRegistered);
    };

    if ($.#isPageModuleRegistered(pageModule)) {
      MountGate.require([]);

      return mount(true, []);
    }

    await Client.fetchPageDigest(
      pageModule,
      (pageDigest) => {
        // The scripts required and the mount waiting are the later navigation's by now.
        if (isSuperseded()) {
          return null;
        }

        LiveReload.recordPageBundle(pageModule, pageDigest);

        MountGate.require([pageDigest]);
        $.#requestPageBundle(pageModule, pageDigest);

        return mount(false, [pageDigest]);
      },
      (_resp) => {
        // The mount that would have closed this transition is never going to run.
        $.#deadEpochs.add(epoch);

        throw new HologramRuntimeError(
          "Failed to fetch page bundle path for: " +
            Interpreter.inspect(pageModule),
        );
      },
    );
  }

  // Hands a page to the browser: as a new history entry, or in place of the entry the tab is on
  // when the page was being loaded into that one.
  static #handToBrowser(url, historyEntryId) {
    if (historyEntryId === null) {
      Hologram.navigateBrowserTo(url);
    } else {
      Hologram.replaceBrowserLocation(url);
    }
  }

  // A page bundle or a chunk could not be fetched. When the mount waits for it, the mount is never
  // going to run, so the epoch is recorded dead: what belongs to it is dropped rather than held
  // (see #runActions). A script no longer required belongs to a navigation a later one superseded,
  // and its failure says nothing about the one now in flight.
  //
  // Answers whether the failure is one the tab is prepared for, which is what keeps it from being
  // raised (see ScriptRegistry.request()): a chunk that only a snapshot restore waits for, which
  // goes on without the snapshot when it cannot have it.
  static #handleScriptFailure(digest) {
    if (MountGate.requires(digest)) {
      MountGate.cancel();
      $.#deadEpochs.add(Math.max($.domEpoch, $.registryEpoch));

      return false;
    }

    return Array.from($.#restoresInFlight).some((digests) =>
      digests.includes(digest),
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

    window.addEventListener("popstate", Hologram.handlePopstateEvent);

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

      // Only restore state for back/forward navigation, not page reloads, and only into the code
      // the snapshot was taken with: this document runs the page's current code, and one that does
      // not fit mounts from the state the server has just rendered instead.
      if (
        !$.#isPageReload() &&
        pageSnapshot &&
        LiveReload.snapshotFits(
          pageSnapshot,
          globalThis.Hologram.initialPageDigest,
          $.#runtimeDigest(),
        )
      ) {
        $.#documentSnapshot = pageSnapshot;
      }
    } else {
      $.#historyId = Utils.uuidv7();
      history.replaceState($.#historyId, null, window.location.pathname);
    }

    await $.#restoreEts();

    // The pair this page was minted, handed over before the store is read: what is found there
    // wins, and this is what the client falls back to when the server refuses it.
    Replica.offer({
      id: globalThis.Hologram.replicaId,
      token: globalThis.Hologram.replicaToken,
    });

    // Awaited HERE, before the mount, which is what lets the restore that follows the mount be
    // synchronous - everything from the mount onwards runs in one continuation, so the first local
    // write cannot land ahead of what a previous page load left.
    await Durability.open();

    // The group this browser's tabs share, joined before the mount and before the stream opens -
    // which is what lets the tab that leads greet the server with sync on its FIRST connect, and
    // stops a follower opening a sync session it would have to drop a moment later.
    //
    // Named for the database and for the user this page mounts under. Per database because tabs on
    // different models cannot share a store, and per user because the leader can only send what
    // the session it holds is allowed to send - a tab still mounted under somebody else must not
    // be sending, or reading, for this one.
    //
    // Nothing to join where there is no store: the tabs of such a browser share nothing, so each
    // is a replica of its own, exactly as every tab was before any of this.
    const database = Durability.databaseName();

    if (database !== null && Durability.mode === "indexeddb") {
      // Read HERE rather than at the mount, because the group cannot be named without it. The
      // mount finds it already read - it has always taken what is held over what the page defines.
      $.#mountData ??= $.#documentMountData();

      await Tabs.join(
        `${database}.${$.#mountData.actorUserId ?? "anonymous"}`,
        {},
      );
    }

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

    // A read-only window onto the write queue, beside the interop hatch above. Nothing in the
    // framework reads it - it is for a devtools panel, a browser-driven test, and whatever step
    // 10's queue surface is built on. Reads only: opening and closing batches is the action
    // lifecycle's, and nothing outside it should reach in.
    globalThis.Hologram.writes = {
      oldestPendingSeq: Batches.oldestPendingSeq,
      pendingCount: Batches.pendingCount,
      rejected: Batches.rejectedSummaries,
    };

    // The same kind of window onto what this browser keeps between page loads: whether it is
    // keeping anything at all, the place it would greet a stream with, the identity it is
    // presenting, and how many writes are still on their way down. Reads only, and nothing in the
    // framework reads them.
    globalThis.Hologram.durability = {
      cursor: () => SyncStream.syncCursor,
      group: () => Tabs.name,
      leader: () => Tabs.leader,
      mode: () => Durability.mode,
      pendingWrites: () => Durability.inFlight,
      persisted: () => Durability.persisted,
      replicaId: () => Replica.id,
      storedBatches: () => Durability.storedBatches,
    };

    delete globalThis.Hologram._pendingJsInteropActions;

    // A page bundle or a chunk announces itself when it has run (see ScriptRegistry), which can be
    // before or after this point: the ones that ran already are defined here, the rest as they
    // announce themselves.
    document.addEventListener("hologram:scriptLoaded", () =>
      Hologram.#defineLoadedScripts(),
    );

    ScriptRegistry.markRequested($.#initialScriptDigests());

    (globalThis.Hologram.initialChunkDigests ?? []).forEach((digest) =>
      $.#chunkDigests.add(digest),
    );

    Hologram.#defineLoadedScripts();

    Hologram.#isInitiated = true;
  }

  // The digests of the scripts the document the server sent carries script elements for, besides
  // the runtime: its page bundle and the chunks its page needs. A document that names none (a test
  // one) has none.
  static #initialScriptDigests() {
    const pageDigest = globalThis.Hologram.initialPageDigest;
    const chunkDigests = globalThis.Hologram.initialChunkDigests ?? [];

    return pageDigest === undefined
      ? chunkDigests
      : [pageDigest, ...chunkDigests];
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

  // Whether a snapshot Back or Forward is about to restore was taken with code other than the
  // page's current one, or the tab holds the page's code in an older version: either way, the
  // page is loaded afresh instead. Asks the server which bundle serves the page now, which is worth
  // a round trip only where live reload runs; if no answer comes, the snapshot is restored as it
  // always was.
  static async #isSnapshotOutdated(pageSnapshot) {
    if (!globalThis.Hologram.config.liveReload) {
      return false;
    }

    let currentPageDigest;

    try {
      currentPageDigest = await Client.fetchPageDigest(pageSnapshot.pageModule);
    } catch {
      return false;
    }

    return (
      !LiveReload.snapshotFits(
        pageSnapshot,
        currentPageDigest,
        $.#runtimeDigest(),
      ) ||
      LiveReload.holdsOldPageBundle(pageSnapshot.pageModule, currentPageDigest)
    );
  }

  // Fetches the chunks the given snapshot was taken with, unless the tab has them, and answers
  // whether they are all in. The state a snapshot holds can carry values of struct types, and
  // their modules, whose struct functions and protocol implementations only those chunks have, so
  // it cannot be restored without them.
  //
  // Unlike every other digest the tab asks for, these were not named by the server just now: a
  // snapshot can be older than the build that serves the app, which no longer has the files. So
  // one that fails to load is no error here, and the caller goes on without the snapshot.
  static async #loadSnapshotChunks(pageSnapshot) {
    // A snapshot taken before snapshots saved their chunks holds none.
    const digests = pageSnapshot.chunkDigests ?? [];

    $.#restoresInFlight.add(digests);
    $.requestChunks(digests);

    try {
      await ScriptRegistry.whenLoaded(digests);

      return true;
    } catch {
      return false;
    } finally {
      $.#restoresInFlight.delete(digests);
    }
  }

  // What the page was mounted with, left behind by the script the server wrote into the page.
  // A navigation reaches it the same way a document load does, by patching in the page the
  // server described, that script included.
  // A navigation carries the mount data as payload fields, which #showNewPage decodes and holds.
  // Shows the page of the history entry the browser went to as the server renders it now, when the
  // entry's snapshot cannot be restored. The page is asked for the way a navigation asks for one,
  // and goes into the entry that exists already. Nothing of the tab is given up for it: the
  // runtime, the realtime stream and the instance id stay.
  static async #loadHistoryEntryPage(historyEntryId, pageSnapshot, epoch) {
    const isSuperseded = () => Math.max($.domEpoch, $.registryEpoch) !== epoch;

    // A mount still waiting belongs to a navigation this one supersedes.
    MountGate.cancel();
    MountGate.require([]);

    // What the browser shows for the entry already, query string and fragment included.
    const {hash, pathname, search} = window.location;
    const pagePath = `${pathname}${search}${hash}`;

    const toParam = Type.tuple([
      pageSnapshot.pageModule,
      pageSnapshot.pageParams,
    ]);

    try {
      await Client.fetchPage(
        toParam,
        (payload) =>
          // The page on its way is a later navigation's by now.
          isSuperseded()
            ? null
            : Hologram.loadNewPage(pagePath, payload, 0, historyEntryId),
        () => {
          if (!isSuperseded()) {
            Hologram.replaceBrowserLocation(pagePath);
          }
        },
      );
    } catch (error) {
      // The mount that would have closed this transition is never going to run.
      if (!isSuperseded()) {
        $.#deadEpochs.add(epoch);
      }

      throw error;
    }
  }

  // A loaded document has no payload, so it carries the same six values as an inline script that
  // defines pageMountData - the one channel markup has for structured state.
  static #loadMountData() {
    const mountData = $.#mountData ?? $.#documentMountData();

    $.#mountData = null;

    Hologram.#pageModule = mountData.pageModule;
    Hologram.#pageParams = mountData.pageParams;

    LiveReload.recordPageBundle(mountData.pageModule, mountData.pageDigest);

    ComponentRegistry.populate(mountData.componentRegistry);

    // Before the first render, so that a prop reading a query answers from the database rather
    // than from nothing - the rows the server read to render this page are the rows those
    // queries need, and they go in through the same ingest the stream uses. Every page visit
    // carries again, which is how navigation needs no server for what it already has.
    //
    // A bundle built before any of this existed carries neither field, and a build with no data
    // model carries no rows - both leave the database as it was.
    if (mountData.syncRows) {
      LocalDatabase.actorUserId = mountData.actorUserId;
      Deltas.apply(mountData.syncRows, {insertOnly: true});

      // A count has no rows behind it, so the rows cannot carry one - the numbers this render
      // answered with travel beside them, and each page visit replaces them the way it replaces
      // what its own props read.
      LocalDatabase.syncCounts = mountData.syncCounts ?? {};
    }

    return mountData;
  }

  static #maybeInitAssetPathRegistry() {
    if (AssetPathRegistry.entries === null) {
      AssetPathRegistry.populate(globalThis.Hologram.assetManifest);
    }
  }

  static #mountPage(isPageModuleRegistered = false) {
    // Nothing pending from the page the user left is dropped here. It is dropped at the instant
    // the user leaves instead - in #showNewPage and handlePopstateEvent - which is the last
    // point at which every pending timer provably belongs to the page being left.
    //
    // Whichever pointer ran ahead during the transition, the mount is where they converge: from
    // here the page on screen and the page the registry answers for are the same page.
    $.domEpoch = $.registryEpoch = Math.max($.domEpoch, $.registryEpoch);

    // Nothing runs until the first render below has written the props - see the flag.
    $.isMounting = true;

    let mountData = null;

    if ($.#shouldLoadMountData) {
      mountData = Hologram.#loadMountData();
    } else {
      $.#shouldLoadMountData = true;
    }

    if (!isPageModuleRegistered) {
      $.#registerPageModule($.#pageModule);
    }

    Hologram.#maybeInitAssetPathRegistry();

    Hologram.prefetchedPages.clear();

    // What arrived during the transition waits behind the mount's own actions, so that a page
    // starts the same way however it was reached: on a document load the page's script dispatches
    // into the shim's buffer, which is enqueued below, after the server inits' actions.
    const waitingEntries = ActionQueue.drain();

    Hologram.queueActionsFromServerInits();

    if (mountData) {
      Hologram.queueSelfEchoes(mountData.selfEchoes);

      App.subscriptionReceiptRegistry.merge(
        mountData.subReceiptAdds,
        mountData.subReceiptDrops,
      );
    }

    Hologram.#enqueuePendingJsInteropActions();

    ActionQueue.append(waitingEntries);

    window.requestAnimationFrame(() => {
      // The registry arrives with every struct's props empty - this render is what writes them, so
      // that the payload doesn't carry each prop value a second time - which is one more reason
      // nothing above may run a handler before this call, and why the queue is held until it is
      // done.
      try {
        $.render();
      } finally {
        // A template expression is app code and can raise, so the flag is cleared on the way out
        // either way. Leaving it set would hold every action from here on.
        $.isMounting = false;
      }

      if ($.#scrollPosition) {
        window.scrollTo($.#scrollPosition[0], $.#scrollPosition[1]);
        $.#scrollPosition = null;
      }

      GlobalRegistry.set("mountedPage", Interpreter.inspect($.#pageModule));

      Hologram.#runActions();
    });
  }

  // Tested implicitely in feature tests
  static async #navigateToPage(toParam) {
    const pagePath = $.#buildPagePath(toParam);

    return Client.fetchPage(
      toParam,
      (payload) => Hologram.loadNewPage(pagePath, payload),
      () => Hologram.navigateBrowserTo(pagePath),
    );
  }

  // Mounts the page once the scripts it requires are loaded (see MountGate): at once when they
  // are, and otherwise when the last of them announces itself.
  static #mountWhenReady(isPageModuleRegistered) {
    MountGate.mountWhenReady(() => {
      try {
        Hologram.#mountPage(isPageModuleRegistered);
      } catch (error) {
        if (error instanceof HologramBoxedError) {
          error.name = error.type;
          error.message = error.text;
        }

        throw error;
      }

      // After the mount, so that the rows the page itself carried are already in - they are the
      // freshest thing this client has, and a stored row fills only what the page said nothing
      // about. Before the connect, so the stream is greeted with the place this browser had
      // already been brought up to rather than with nothing.
      Hologram.#restoreDurable();

      // SSE must open AFTER `#mountPage()` because the handshake payload
      // includes the receipts merged from `pageMountData.subReceiptAdds` -
      // connecting earlier would send an empty receipts list.
      if (Sse.eventSource === null) {
        Sse.connect();
      }
    });
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

  // Mirrors Hologram.Router.Helpers.page_bundle_path/2
  static #pageBundlePath(pageModule, pageDigest) {
    return `/hologram/page-${Interpreter.moduleExName(pageModule)}-${pageDigest}.js`;
  }

  // A value the server sent as JSON, or undefined when it sent none - a build with no data model
  // carries no rows, and neither does a payload from a server that predates them.
  static #parseMountJson(json) {
    return json === undefined ? undefined : JSON.parse(json);
  }

  static #pageSnapshotKey(historyId) {
    return `${$.#PAGE_SNAPSHOT_KEY_PREFIX}${historyId}`;
  }

  // Goes where a page's middleware said to go instead, by asking for the page it named.
  //
  // A target outside the app carries no page to ask for, so the browser takes it. The hop limit is
  // there because a redirect can point at a page that redirects again: a cycle would otherwise
  // fetch forever, silently.
  static #followRedirect(payload, hopCount, historyEntryId) {
    if (!payload.pageModule) {
      $.#handToBrowser(payload.to, historyEntryId);
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
        Hologram.loadNewPage(
          payload.to,
          nextPayload,
          hopCount + 1,
          historyEntryId,
        ),
      () => $.#handToBrowser(payload.to, historyEntryId),
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

    // This line is the last instant that is still only the page being left - nothing of the
    // destination is on screen, none of its listeners are attached, none of its scripts have run
    // - so everything armed here provably belongs to the page being left.
    $.#disarmLeftPage();

    // What was awaiting belongs to the page being left, and the destination may hold the same
    // cids. Emptied here for the same reason the timers are cancelled here.
    $.#awaitingTargets.clear();

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
    //
    // The mount waits for the page's bundle, unless the tab holds the page's code already, and for
    // the chunks the page needs: the ones it preloads and the ones its state holds values for.
    const chunkDigests = payload.chunks ?? [];

    if (isPageModuleRegistered) {
      MountGate.require(chunkDigests);
    } else {
      MountGate.require([payload.pageDigest, ...chunkDigests]);
      $.#requestPageBundle(pageModule, payload.pageDigest);
    }

    $.requestChunks(chunkDigests);

    // Readable before the patch, rather than as a side effect of a script the patch inserts and
    // the browser then runs. The page module is already decoded above, so it is reused.
    // The data-layer values travel as JSON rather than as boxed terms, the way the inline script
    // inlines them: the local database reads them, not transpiled code. A server that predates
    // them sends none, which the mount reads as nothing to ingest.
    $.#mountData = {
      actorUserId: $.#parseMountJson(payload.actorUserId),
      componentRegistry: Interpreter.evaluateJavaScriptExpression(
        payload.componentRegistry,
      ),
      pageDigest: payload.pageDigest,
      pageModule: pageModule,
      pageParams: Interpreter.evaluateJavaScriptExpression(payload.pageParams),
      selfEchoes: Interpreter.evaluateJavaScriptExpression(payload.selfEchoes),
      subReceiptAdds: Interpreter.evaluateJavaScriptExpression(
        payload.subReceiptAdds,
      ),
      subReceiptDrops: Interpreter.evaluateJavaScriptExpression(
        payload.subReceiptDrops,
      ),
      syncCounts: $.#parseMountJson(payload.syncCounts),
      syncRows: $.#parseMountJson(payload.syncRows),
    };

    // See: docs/navigation_payload_wire_format.md
    const tree = Renderer.decodeTree(payload.tree);
    const newVirtualDocument = Renderer.renderTree(tree);

    $.#dropPageBundleScript(newVirtualDocument, pageModule, payload.pageDigest);

    Hologram.virtualDocument = Vdom.patchVirtualDocument(
      Hologram.virtualDocument,
      newVirtualDocument,
    );

    // A page whose code the tab holds mounts now. The mount of any other waits for its bundle to
    // announce itself.
    $.#mountWhenReady(isPageModuleRegistered);
  }

  // Deps: [:maps.get/2, :maps.get/3, :maps.put/3]
  static #processActionResult(
    resultComponentStruct,
    name,
    target,
    startTime,
    epoch,
  ) {
    // Sealed BEFORE the render below, so the one frame that follows shows the action's state
    // change and its data change together - which is the whole point of the batch boundary being
    // the action.
    Batches.close();

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

    // After the render rather than before it: what the user sees does not wait on the network.
    Batches.flush();

    if (!Type.isNil(nextAction)) {
      if (Type.isNil(Erlang_Maps["get/2"](Type.atom("target"), nextAction))) {
        nextAction = Erlang_Maps["put/3"](
          Type.atom("target"),
          target,
          nextAction,
        );
      }

      const delay = Erlang_Maps["get/3"](
        Type.atom("delay"),
        nextAction,
        Type.integer(0),
      );

      // A next action belongs to whatever page its parent belonged to, so it inherits the
      // parent's stamp rather than reading the epoch afresh. That matters most when the parent
      // was asynchronous: its promise can resolve after a navigation, and the inherited stamp is
      // what makes the next action drop instead of landing on a page that never produced it.
      //
      // A next action with no delay runs before the browser paints, so that two components a
      // chain changes are never painted disagreeing. The browser paints between tasks, and a
      // timer would start a new one. The walk that ran a synchronous parent takes the action
      // once the parent is done. An asynchronous parent resolves when no walk is running, and the
      // microtask starts one - a microtask runs before the paint, and an error raised in it is an
      // "error" event, the way a timer-driven action's is, not the rejection of the parent's
      // promise (see the result.finally in #runActions). After a synchronous parent the
      // microtask's walk finds nothing left to do. A chain with no delay doesn't yield until it
      // ends, so an action that puts itself again with no delay is an infinite loop.
      if (delay.value === 0n) {
        ActionQueue.enqueue(nextAction, epoch);
        queueMicrotask(() => $.#runActions());
      } else {
        Hologram.scheduleAction(nextAction, epoch);
      }
    }

    if (!Type.isNil(nextPage)) {
      $.#navigateToPage(nextPage);
    }
  }

  static #registerPageModule(pageModule) {
    $.#registeredPageModules.add(pageModule.value);
  }

  // Fetches a page's own code, which announces itself when it has run (see ScriptRegistry). A
  // bundle that cannot be fetched ends the navigation: see #handleScriptFailure.
  static #requestPageBundle(pageModule, pageDigest) {
    ScriptRegistry.request(
      [{digest: pageDigest, path: $.#pageBundlePath(pageModule, pageDigest)}],
      (digest) => $.#handleScriptFailure(digest),
    );
  }

  // Takes up what a previous page load left - the place to resume the stream from, the number to
  // count batches on from, and the batches it never managed to send - and answers nothing on every
  // visit after the first, since the runtime's page-script listener fires again on each
  // client-side navigation and this runs once per page visit.
  static #restoreDurable() {
    const resumed = Durability.restore(Tabs.leader);

    if (resumed === null) {
      return;
    }

    SyncStream.syncCursor = resumed.cursor;
    Batches.resumeFrom(resumed.seq);
    Batches.adopt(resumed.batches);

    // Everything this tab starts with is in place, so what the group has said since may land on it
    // - and whatever arrived while it was starting up is applied now, in the order it arrived.
    Tabs.ready();

    // And what the store could not tell it is asked for: the completeness scopes, which nothing
    // writes down, and the place and the identity as they stand in the tab that has them.
    Tabs.post({kind: "joined"});

    // The third thing that wakes the sender, beside an action finishing and the stream opening.
    // It is needed rather than tidy: the stream is connected before the mount, so it can have
    // opened - and flushed an empty queue - before these batches were taken up. Without this they
    // would wait for the user to do something.
    Batches.flush();
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

    // A restore swaps the registry while the previous page is still on screen - the mirror of a
    // forward navigation, where the markup runs ahead instead. The epoch of what the registry
    // answers for was advanced when the restore was decided on; the mount brings the displayed
    // side level.
    ComponentRegistry.populate(componentRegistryEntries);

    App.instanceId = instanceId;
    App.subscriptionReceiptRegistry.populate(subscriptionReceipts);

    Hologram.#pageModule = pageModule;
    Hologram.#pageParams = pageParams;

    $.#scrollPosition = scrollPosition;
    $.#shouldLoadMountData = false;
  }

  // Walks the queue and runs every entry that can run, in order, until the walk is over or the
  // page has to wait. The page waits while the client is mid-transition (the entries belong to the
  // page being moved to, which cannot answer until it mounts), while the page is mounting (its
  // first render has not written the props yet), and while a render is on the stack (the DOM it
  // walks is mid-update, and an action's own render would walk the same tree behind it). A
  // component waits while an action of its own is awaiting, and so do its later entries: a later
  // entry never overtakes an earlier one for the same component. Whoever ends a wait runs the
  // queue again: the settled action, the mount, the finished render.
  //
  // An action stamped with a page that has been left, or whose navigation failed before it could
  // mount, is dropped when the walk reaches it - nothing can answer for it any more. The warning is
  // the trace a button that appears to do nothing leaves behind.
  //
  // One action is no reason to drop the rest: a single focusout flushes every pending slot on the
  // element at once, so a run of several is the ordinary case, and they have nothing to do with one
  // another. Every one is delivered and the first error is raised once the walk is over - the same
  // bargain the debouncer makes with the callbacks it flushes.
  // Deps: [:maps.get/2]
  static #runActions() {
    if ($.#isRunningActions) {
      return;
    }

    $.#isRunningActions = true;

    let firstError;

    try {
      // The components this walk may not run an action for: one whose action is awaiting, and one
      // whose earlier entry was passed over, so that a later entry for it does not overtake it.
      const blockedTargets = new Set($.#awaitingTargets.keys());
      let index = 0;

      while (index < ActionQueue.entries.length) {
        const {action, epoch} = ActionQueue.entries[index];
        const currentEpoch = Math.max($.domEpoch, $.registryEpoch);

        // Dropped whatever the page is doing: a stale entry has nothing to wait for.
        if (epoch < currentEpoch || $.#deadEpochs.has(epoch)) {
          ActionQueue.removeAt(index);

          console.warn(
            "Hologram: dropped an action dispatched on a page that has been left:",
            Interpreter.inspect(
              Erlang_Maps["get/2"](Type.atom("name"), action),
            ),
          );

          continue;
        }

        if ($.domEpoch !== $.registryEpoch || $.isMounting || $.isRendering) {
          break;
        }

        // A cid is text by construction, and reading a bitstring's text fills in nothing on it -
        // encoding it as a map key would cache its bytes on the action's own struct.
        const targetKey = Bitstring.toText(
          Erlang_Maps["get/2"](Type.atom("target"), action),
        );

        if (blockedTargets.has(targetKey)) {
          index++;
          continue;
        }

        ActionQueue.removeAt(index);

        let result;

        try {
          result = Hologram.executeAction(action, epoch);
        } catch (error) {
          firstError ??= error;
          continue;
        }

        if (result instanceof Promise) {
          $.#awaitingTargets.set(targetKey, epoch);
          blockedTargets.add(targetKey);

          // Resumed from a microtask rather than from the promise's own continuation, so that an
          // action raising in the resumed run surfaces as an uncaught error, the way every
          // timer-driven action does, and not as the rejection of a promise nobody holds. The
          // promise's own rejection still reaches the "unhandledrejection" listener: finally()
          // passes it through. A microtask and not a timer, so that what waited behind the action
          // runs before the browser paints - a next action with no delay the action put on its own
          // component among them, which the walk its result started passed over while the
          // component was still awaiting.
          result.finally(() => {
            // The page may have been left since, which empties the map, and the destination may
            // be awaiting an action of its own under the same cid - that entry is not this one's.
            if ($.#awaitingTargets.get(targetKey) === epoch) {
              $.#awaitingTargets.delete(targetKey);
            }

            queueMicrotask(() => Hologram.#runActions());
          });
        }
      }
    } finally {
      $.#isRunningActions = false;
    }

    if (firstError !== undefined) {
      throw firstError;
    }
  }

  // The digest of the runtime bundle this document runs, read from the path the asset manifest the
  // boot script left holds for it.
  static #runtimeDigest() {
    const path = globalThis.Hologram.assetManifest?.["hologram/runtime.js"];

    return path?.match(/-([^-]+)\.js$/)?.[1] ?? null;
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
    // The entry's snapshot is still waiting to be restored, and nothing has taken its place: the
    // page is not mounted yet, so there is no state to save over it.
    if ($.#documentSnapshot !== null) {
      return;
    }

    const pageSnapshot = {
      // Every chunk the tab has loaded, not only the ones this page's state needs: which of them
      // the state needs is not known here, and a chunk too many costs a restore one cached fetch.
      chunkDigests: Array.from($.#chunkDigests).filter((digest) =>
        ScriptRegistry.isLoaded([digest]),
      ),
      componentRegistryEntries: ComponentRegistry.entries,
      instanceId: App.instanceId,
      pageDigest: LiveReload.heldPageDigest(Hologram.#pageModule),
      pageModule: Hologram.#pageModule,
      pageParams: Hologram.#pageParams,
      runtimeDigest: $.#runtimeDigest(),
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
}

const $ = Hologram;
