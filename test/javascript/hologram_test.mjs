"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
  UUID_REGEX,
} from "./support/helpers.mjs";

import CallStack from "../../assets/js/erts/call_stack.mjs";
import Client from "../../assets/js/client.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Config from "../../assets/js/config.mjs";
import EventListenerRegistry from "../../assets/js/event_listener_registry.mjs";
import EventListeners from "../../assets/js/event_listeners.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramBoxedError from "../../assets/js/errors/boxed_error.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import InitActionQueue from "../../assets/js/init_action_queue.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";
import UncaughtErrorOverlay from "../../assets/js/uncaught_error_overlay.mjs";
import Vdom from "../../assets/js/vdom.mjs";

import {defineModule7Fixture} from "./support/fixtures/hologram/module_7.mjs";

defineRuntimeGlobals();
registerWebApis();
defineModule7Fixture();

const cid1 = Type.bitstring("my_component_1");
const module7 = Type.alias("Hologram.Test.Fixtures.Module7");

describe("Hologram", () => {
  describe("dispatchAction()", () => {
    let clock, executeActionStub;

    beforeEach(() => {
      clock = sinon.useFakeTimers();

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);
    });

    afterEach(() => {
      clock.restore();
      executeActionStub.restore();
    });

    // The counterpart of the hold covered in loadNewPage(): with no page swap in flight the page
    // on screen is the page the registry answers for, so there is nothing to wait for.
    it("dispatches an action right away when no page swap is in flight", () => {
      Hologram.dispatchAction("my_action", "my_component_1", {a: 1});

      clock.tick(0);

      sinon.assert.calledOnce(executeActionStub);

      const action = executeActionStub.firstCall.args[0];

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("name"), action),
        Type.atom("my_action"),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("target"), action),
        Type.bitstring("my_component_1"),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("params"), action),
        Type.map([[Type.atom("a"), Type.integer(1)]]),
      );
    });
  });

  describe("executeAction()", () => {
    let callNamedFunctionStub, renderStub;

    const actionFor = (target) =>
      Type.actionStruct({
        name: Type.atom("test_action"),
        params: Type.map(),
        target: target,
      });

    beforeEach(() => {
      ComponentRegistry.clear();

      callNamedFunctionStub = sinon
        .stub(Interpreter, "callNamedFunction")
        .callsFake((_module, _fun, _args, _context) =>
          Type.componentStruct({state: Type.map()}),
        );

      // The result of a dispatch is rendered, which needs a page these tests don't mount.
      renderStub = sinon.stub(Hologram, "render").callsFake(() => null);
    });

    afterEach(() => {
      ComponentRegistry.clear();
      sinon.restore();
    });

    // The registry answers with plain null for a cid it does not hold, and null reaching
    // callNamedFunction faults on reading a module name off it.
    it("raises for a target the registry does not hold", () => {
      assertBoxedError(
        () => Hologram.executeAction(actionFor(Type.bitstring("nonexistent"))),
        "ArgumentError",
        'invalid action target, there is no component with CID: "nonexistent"',
      );
    });

    it("doesn't dispatch to a target the registry does not hold", () => {
      try {
        Hologram.executeAction(actionFor(Type.bitstring("nonexistent")));
      } catch {
        // Asserted on in the case above - what matters here is what didn't run.
      }

      sinon.assert.notCalled(callNamedFunctionStub);
    });

    it("dispatches to a registered target", () => {
      ComponentRegistry.putEntry(
        cid1,
        Type.map([
          [Type.atom("module"), module7],
          [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
        ]),
      );

      Hologram.executeAction(actionFor(cid1));

      sinon.assert.calledOnce(callNamedFunctionStub);
      sinon.assert.calledOnce(renderStub);

      assert.deepStrictEqual(callNamedFunctionStub.firstCall.args[0], module7);

      assert.deepStrictEqual(
        callNamedFunctionStub.firstCall.args[1],
        Type.atom("action"),
      );
    });

    // A next action is a continuation of the one that produced it, so it belongs to the same page
    // - which is not necessarily the page current by the time it is scheduled, since the parent
    // may have been asynchronous.
    describe("next action", () => {
      let clock, nextActionStruct, scheduleActionStub;

      beforeEach(() => {
        clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        nextActionStruct = Type.actionStruct({
          name: Type.atom("the_next_action"),
          params: Type.map(),
          target: cid1,
        });

        ComponentRegistry.putEntry(
          cid1,
          Type.map([
            [Type.atom("module"), module7],
            [
              Type.atom("struct"),
              Type.componentStruct({nextAction: Type.nil()}),
            ],
          ]),
        );

        callNamedFunctionStub.callsFake((_module, _fun, _args, _context) =>
          Type.componentStruct({
            nextAction: nextActionStruct,
            state: Type.map(),
          }),
        );

        scheduleActionStub = sinon
          .stub(Hologram, "scheduleAction")
          .callsFake((_action, _epoch) => null);
      });

      afterEach(() => clock.restore());

      it("inherits the epoch its parent carried", () => {
        Hologram.executeAction(actionFor(cid1), 7);

        sinon.assert.calledOnceWithExactly(
          scheduleActionStub,
          nextActionStruct,
          7,
        );
      });

      // Reading the epoch afresh at this point would stamp the next action with whatever page the
      // client has reached, which is exactly how a late continuation lands on a stranger.
      it("does not take the epoch current when it is scheduled", () => {
        Hologram.domEpoch = 3;
        Hologram.registryEpoch = 3;

        try {
          Hologram.executeAction(actionFor(cid1), 1);

          sinon.assert.calledOnceWithExactly(
            scheduleActionStub,
            nextActionStruct,
            1,
          );
        } finally {
          Hologram.domEpoch = 0;
          Hologram.registryEpoch = 0;
        }
      });
    });
  });

  describe("executeLoadPrefetchedPageAction()", () => {
    let eventTargetNode, loadNewPageStub;

    const payload = {type: "page"};

    const loadPrefetchedPageAction = Type.actionStruct({
      name: Type.atom("__load_prefetched_page__"),
      params: Type.map([[Type.atom("to"), module7]]),
      target: cid1,
    });

    const pagePath = "/hologram-test-fixtures-module7";

    beforeEach(() => {
      loadNewPageStub = sinon
        .stub(Hologram, "loadNewPage")
        .callsFake((_pagePath, _payload) => null);

      eventTargetNode = {id: "dummy_event_target_node"};
    });

    afterEach(() => Hologram.loadNewPage.restore());

    it("adds a Hologram ID to an event target DOM node that doesn't have one", () => {
      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      assert.match(eventTargetNode.__hologramId__, UUID_REGEX);
    });

    it("doesn't add a Hologram ID to an event target DOM node that already has one", () => {
      eventTargetNode.__hologramId__ = "dummy_hologram_id";

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      assert.equal(eventTargetNode.__hologramId__, "dummy_hologram_id");
    });

    it("confirms navigate if page HTML hasn't been fetched yet", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            payload: null,
            isNavigateConfirmed: false,
            pagePath: pagePath,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(mapValue, {
        payload: null,
        isNavigateConfirmed: true,
        pagePath: pagePath,
        timestamp: mapValue.timestamp,
      });

      sinon.assert.notCalled(loadNewPageStub);
    });

    it("loads page if page HTML has been already fetched", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            payload: payload,
            isNavigateConfirmed: false,
            pagePath: pagePath,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(loadNewPageStub, pagePath, payload);
    });

    // Dropping the entry instead would leave the link dead: the click looks the target up here,
    // and an entry that is not there does nothing at all.
    it("hands the target to the browser when the prefetch found no page", () => {
      const leaveAppStub = sinon.stub(Hologram, "leaveApp");

      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            isNavigateConfirmed: false,
            isPage: false,
            pagePath: pagePath,
            payload: null,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(leaveAppStub, pagePath);
      sinon.assert.notCalled(loadNewPageStub);

      leaveAppStub.restore();
    });

    it("is a no-op if there is no prefeteched pages map entry for the given map key", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.notCalled(loadNewPageStub);
    });
  });

  describe("executePrefetchPageAction()", () => {
    let clientFetchPageDataStub,
      eventTargetNode,
      handlePrefetchPageSuccessStub,
      successCallbacks;

    const pagePath = "/hologram-test-fixtures-module7";

    const prefetchPageAction = Type.actionStruct({
      name: Type.atom("__prefetch_page__"),
      params: Type.map([[Type.atom("to"), module7]]),
      target: cid1,
    });

    const resp = "dummy_resp";

    beforeEach(() => {
      successCallbacks = [];

      clientFetchPageDataStub = sinon
        .stub(Client, "fetchPage")
        .callsFake((_toParam, successCallback) => {
          successCallbacks.push(successCallback);
        });

      handlePrefetchPageSuccessStub = sinon
        .stub(Hologram, "handlePrefetchPageSuccess")
        .callsFake((_mapKey, _resp) => null);

      eventTargetNode = {id: "dummy_event_target_node"};
    });

    afterEach(() => {
      Client.fetchPage.restore();
      Hologram.handlePrefetchPageSuccess.restore();
    });

    it("adds a Hologram ID to an event target DOM node that doesn't have one", () => {
      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);
      assert.match(eventTargetNode.__hologramId__, UUID_REGEX);
    });

    it("doesn't add a Hologram ID to an event target DOM node that already has one", () => {
      eventTargetNode.__hologramId__ = "dummy_hologram_id";

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      assert.equal(eventTargetNode.__hologramId__, "dummy_hologram_id");
    });

    it("prefetches the page if there is no previous prefetch in progress", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      const mapKey = `${eventTargetNode.__hologramId__}:/hologram-test-fixtures-module7`;

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(mapValue, {
        isNavigateConfirmed: false,
        isPage: true,
        pagePath: pagePath,
        payload: null,
        timestamp: mapValue.timestamp,
      });

      assert.isAtMost(Math.abs(Date.now() - mapValue.timestamp), 100);

      sinon.assert.calledOnceWithExactly(
        clientFetchPageDataStub,
        module7,
        successCallbacks[0],
        sinon.match.func,
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageSuccessStub,
        mapKey,
        resp,
      );
    });

    it("prefetches the page if the previous prefetch has timed out", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            dummyKey: "dummy_value",
            timestamp: Date.now() - Config.fetchPageTimeoutMs - 1,
          },
        ],
      ]);

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(Hologram.prefetchedPages.get(mapKey), {
        isNavigateConfirmed: false,
        isPage: true,
        pagePath: pagePath,
        payload: null,
        timestamp: mapValue.timestamp,
      });

      assert.isAtMost(Math.abs(Date.now() - mapValue.timestamp), 100);

      sinon.assert.calledOnceWithExactly(
        clientFetchPageDataStub,
        module7,
        successCallbacks[0],
        sinon.match.func,
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageSuccessStub,
        mapKey,
        resp,
      );
    });

    it("doesn't prefetch the page if the previous prefetch is in progress and hasn't timed out", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      const mapValue = {
        dummyKey: "dummy_value",
        timestamp: Date.now(),
      };

      Hologram.prefetchedPages = new Map([[mapKey, mapValue]]);

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));
      assert.equal(Hologram.prefetchedPages.get(mapKey), mapValue);

      sinon.assert.notCalled(clientFetchPageDataStub);
      sinon.assert.notCalled(handlePrefetchPageSuccessStub);
    });
  });

  describe("handleUiEvent()", () => {
    let executeActionStub,
      clientSendCommandStub,
      executeLoadPrefetchedPageActionStub,
      executePrefetchPageActionStub,
      scheduleActionStub;

    const actionSpecDom = Type.keywordList([
      [Type.atom("text"), Type.bitstring("my_action")],
    ]);

    // Example: $click={nil}
    const disabledSpecDom = Type.keywordList([
      [Type.atom("expression"), Type.tuple([Type.nil()])],
    ]);

    const defaultTarget = cid1;
    const eventType = "click";

    const notIgnoredEvent = {
      clientX: 10,
      clientY: 20,
      movementX: 5,
      movementY: 15,
      offsetX: 30,
      offsetY: 40,
      pageX: 1,
      pageY: 2,
      pointerType: "mouse",
      screenX: 100,
      screenY: 200,
      preventDefault: () => null,
      target: {id: "dummy_node"},
    };

    beforeEach(() => {
      clientSendCommandStub = sinon
        .stub(Client, "sendCommand")
        .callsFake((_command) => null);

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);

      executeLoadPrefetchedPageActionStub = sinon
        .stub(Hologram, "executeLoadPrefetchedPageAction")
        .callsFake((_action, _eventTargetNode) => null);

      executePrefetchPageActionStub = sinon
        .stub(Hologram, "executePrefetchPageAction")
        .callsFake((_action, _eventTargetNode) => null);

      scheduleActionStub = sinon
        .stub(Hologram, "scheduleAction")
        .callsFake((_action) => null);
    });

    afterEach(() => {
      Client.sendCommand.restore();
      Hologram.executeAction.restore();
      Hologram.executeLoadPrefetchedPageAction.restore();
      Hologram.executePrefetchPageAction.restore();
      Hologram.scheduleAction.restore();
    });

    it("event is ignored", () => {
      const ignoredEvent = {
        clientX: 10,
        clientY: 20,
        movementX: 5,
        movementY: 15,
        offsetX: 30,
        offsetY: 40,
        pageX: 1,
        pageY: 2,
        pointerType: "mouse",
        screenX: 100,
        screenY: 200,
        ctrlKey: true,
        preventDefault: () => null,
      };

      Hologram.handleUiEvent(
        ignoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);
    });

    it("regular action without delay", () => {
      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        params: Type.map([
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(executeActionStub, expectedAction, 0);
      sinon.assert.notCalled(scheduleActionStub);
    });

    // The window a forward navigation opens: the destination's markup is on screen and clickable
    // while the registry still answers for the page being left, so the click waits for the mount
    // rather than resolving against a page that never carried the button.
    it("holds a click that lands while the destination is still mounting", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.domEpoch = 1;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          actionSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.notCalled(executeActionStub);
        sinon.assert.notCalled(scheduleActionStub);

        // A held click and a dropped one both leave executeAction uncalled. The absence of the
        // warning is what says this one is waiting for its page.
        sinon.assert.notCalled(warnStub);
      } finally {
        Hologram.domEpoch = 0;
        warnStub.restore();
      }
    });

    // The mirror window, opened by a history restoration: the registry has moved on to the page
    // being restored while the page the user clicked is still on screen, so the click is aimed at
    // a page that has been left and nothing can answer for it.
    it("drops a click from a page a restore has moved past", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.registryEpoch = 1;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          actionSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.notCalled(executeActionStub);
        sinon.assert.notCalled(scheduleActionStub);
        sinon.assert.calledOnce(warnStub);
      } finally {
        Hologram.registryEpoch = 0;
        warnStub.restore();
      }
    });

    // The whole reason the stamp is read when the event fires rather than when the dispatch runs:
    // a debounce or a throttle can hold a dispatch across a navigation, and it still belongs to
    // the page the user was looking at. Reading the epoch late would silently re-home it to
    // whatever page is on screen by then.
    it("stamps a deferred dispatch with the page the event happened on", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          actionSpecDom,
          defaultTarget,
        );

        // A navigation between the event and the dispatch it was held back from.
        Hologram.domEpoch = 1;

        dispatch();

        // Dropped, because it belongs to the page that has been left. Read late, the stamp would
        // have matched the destination and this would have been held for its mount instead.
        sinon.assert.notCalled(executeActionStub);
        sinon.assert.notCalled(scheduleActionStub);
        sinon.assert.calledOnce(warnStub);
      } finally {
        Hologram.domEpoch = 0;
        warnStub.restore();
      }
    });

    it("regular action with delay", () => {
      const delayedActionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("my_delayed_action")],
              [Type.atom("delay"), Type.integer(500)],
            ]),
          ]),
        ],
      ]);

      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        delayedActionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("my_delayed_action"),
        params: Type.map([
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
        delay: Type.integer(500),
      });

      // The epoch is the page the user acted on, recorded when the event fired rather than when
      // the delay elapses.
      sinon.assert.calledOnceWithExactly(
        scheduleActionStub,
        expectedAction,
        Hologram.domEpoch,
      );

      sinon.assert.notCalled(executeActionStub);
    });

    it("navigate to prefetched page action", () => {
      // Spec DOM: [expression: {[action: :__load_prefetched_page__, params: %{to: MyPage}]}],
      // which is equivalent to [{:expression, {[{:action, :__load_prefetched_page__}, {:params, %{to: MyPage}}]}}]
      const actionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("__load_prefetched_page__")],
              [
                Type.atom("params"),
                Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
              ],
            ]),
          ]),
        ],
      ]);

      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("__load_prefetched_page__"),
        params: Type.map([
          [Type.atom("to"), Type.alias("MyPage")],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(
        executeLoadPrefetchedPageActionStub,
        expectedAction,
        notIgnoredEvent.target,
      );
    });

    it("prefetch page action", () => {
      // Spec DOM: [expression: {[action: :__prefetch_page__, params: %{to: MyPage}]}],
      // which is equivalent to [{:expression, {[{:action, :__prefetch_page__}, {:params, %{to: MyPage}}]}}]
      const actionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("__prefetch_page__")],
              [
                Type.atom("params"),
                Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
              ],
            ]),
          ]),
        ],
      ]);

      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("__prefetch_page__"),
        params: Type.map([
          [Type.atom("to"), Type.alias("MyPage")],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(
        executePrefetchPageActionStub,
        expectedAction,
        notIgnoredEvent.target,
      );
    });

    it("command", () => {
      // Example: $click={command: :my_command}
      // Spec DOM: [expression: {[command: :my_command]}],
      // which is equivalent to [{:expression, {[{:command, :my_command}]}}]
      const commandSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([[Type.atom("command"), Type.atom("my_command")]]),
          ]),
        ],
      ]);

      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        commandSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);

      const expectedCommand = Type.commandStruct({
        name: Type.atom("my_command"),
        params: Type.map([
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(
        clientSendCommandStub,
        expectedCommand,
      );
    });

    it("does not prevent default when isDefaultAllowed is true", () => {
      // KeyboardEvent.isDefaultAllowed is true
      const preventDefault = sinon.spy();

      const keyboardEvent = {
        altKey: false,
        code: "Enter",
        ctrlKey: false,
        key: "Enter",
        metaKey: false,
        repeat: false,
        shiftKey: false,
        preventDefault,
        target: {id: "dummy_node"},
      };

      const dispatch = Hologram.handleUiEvent(
        keyboardEvent,
        "keydown",
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(preventDefault);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("prevents default when isDefaultAllowed is false", () => {
      // SubmitEvent.isDefaultAllowed is false, so a native form submit is prevented by default

      const preventDefault = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault,
      };

      Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.calledOnce(preventDefault);
    });

    it("allows the default when allowDefault is set", () => {
      // The binding's allow_default modifier opts out of the framework preventDefault, even for
      // an isDefaultAllowed: false event like submit.

      const preventDefault = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault,
      };

      const dispatch = Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
        true,
      );

      dispatch();

      sinon.assert.notCalled(preventDefault);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("prevents the default when forcePreventDefault is set", () => {
      // The binding's prevent_default modifier forces the framework preventDefault, even for an
      // isDefaultAllowed: true event like keydown.

      const preventDefault = sinon.spy();

      const keyboardEvent = {
        altKey: false,
        code: "Enter",
        ctrlKey: false,
        key: "Enter",
        metaKey: false,
        repeat: false,
        shiftKey: false,
        preventDefault,
        target: {id: "dummy_node"},
      };

      const dispatch = Hologram.handleUiEvent(
        keyboardEvent,
        "keydown",
        actionSpecDom,
        defaultTarget,
        false,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(preventDefault);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("does not stop propagation by default", () => {
      const stopPropagation = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault: () => null,
        stopPropagation,
      };

      const dispatch = Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(stopPropagation);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("stops propagation when stopPropagation is set", () => {
      // The binding's stop_propagation modifier stops the event from bubbling past the bound
      // element while the action still dispatches.

      const stopPropagation = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault: () => null,
        stopPropagation,
      };

      const dispatch = Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(stopPropagation);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("does not stop propagation when the event is ignored", () => {
      // ClickEvent ignores a Ctrl+click, so the event edge work doesn't run for it.

      const stopPropagation = sinon.spy();

      const ignoredEvent = {
        clientX: 10,
        clientY: 20,
        movementX: 5,
        movementY: 15,
        offsetX: 30,
        offsetY: 40,
        pageX: 1,
        pageY: 2,
        pointerType: "mouse",
        screenX: 100,
        screenY: 200,
        ctrlKey: true,
        preventDefault: () => null,
        stopPropagation,
      };

      Hologram.handleUiEvent(
        ignoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
        false,
        true,
      );

      sinon.assert.notCalled(stopPropagation);
    });

    it("tolerates an event payload without a stopPropagation method", () => {
      // A resize binding's ResizeObserverEntry is not a DOM event and has no stopPropagation
      // method, so the call is skipped instead of crashing.

      const resizeObserverEntry = {
        target: {},
        borderBoxSize: [{blockSize: 10, inlineSize: 20}],
        contentBoxSize: [{blockSize: 8, inlineSize: 18}],
        devicePixelContentBoxSize: [{blockSize: 20, inlineSize: 40}],
      };

      const dispatch = Hologram.handleUiEvent(
        resizeObserverEntry,
        "resize",
        actionSpecDom,
        defaultTarget,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(executeActionStub);
    });

    it("tolerates an event payload without a preventDefault method", () => {
      // A resize binding's ResizeObserverEntry is not a DOM event and has no preventDefault
      // method, so a forced preventDefault is skipped instead of crashing.

      const resizeObserverEntry = {
        target: {},
        borderBoxSize: [{blockSize: 10, inlineSize: 20}],
        contentBoxSize: [{blockSize: 8, inlineSize: 18}],
        devicePixelContentBoxSize: [{blockSize: 20, inlineSize: 40}],
      };

      const dispatch = Hologram.handleUiEvent(
        resizeObserverEntry,
        "resize",
        actionSpecDom,
        defaultTarget,
        false,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(executeActionStub);
    });

    it("returns null for a disabled binding", () => {
      const result = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        disabledSpecDom,
        defaultTarget,
      );

      assert.isNull(result);

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);
    });

    it("does not prevent default for a disabled binding", () => {
      // SubmitEvent.isDefaultAllowed is false, so an enabled binding would prevent the default.

      const preventDefault = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault,
      };

      Hologram.handleUiEvent(
        submitEvent,
        "submit",
        disabledSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(preventDefault);
    });

    it("does not stop propagation for a disabled binding when stopPropagation is set", () => {
      const stopPropagation = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault: () => null,
        stopPropagation,
      };

      Hologram.handleUiEvent(
        submitEvent,
        "submit",
        disabledSpecDom,
        defaultTarget,
        false,
        true,
      );

      sinon.assert.notCalled(stopPropagation);
    });

    it("dispatches a reach event with an empty payload", () => {
      const dispatch = Hologram.handleUiEvent(
        {target: {id: "dummy_node"}},
        "reach_bottom",
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      const expectedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        params: Type.map([[Type.atom("event"), Type.map()]]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(executeActionStub, expectedAction, 0);
    });
  });

  describe("loadNewPage()", () => {
    let assignedUrls, assignStub, fetchPageStub;

    const encodedModule7 = `Type.atom("Elixir.Hologram.Test.Fixtures.Module7")`;
    const encodedNoParams = "Type.map([])";

    const redirectTo = (to, encodedPageModule = encodedModule7) => ({
      pageModule: encodedPageModule,
      pageParams: encodedNoParams,
      to: to,
      type: "redirect",
    });

    // The wire form: an element is [tagName, attributes, children], attributes are a flat
    // name/value run, and text is a bare string.
    const wireElement = (tagName, attributes = [], children = []) => [
      tagName,
      attributes,
      children,
    ];

    const wireBundleScript = (pageDigest) =>
      wireElement("script", ["src", `/hologram/page-${pageDigest}.js`]);

    // What the server sends: the whole document, the page's own bundle script included.
    const treeFor = (pageDigest, bodyText) => [
      wireElement(
        "html",
        [],
        [
          wireElement("head", [], [wireBundleScript(pageDigest)]),
          wireElement("body", [], [bodyText]),
        ],
      ),
    ];

    // The mount data the server used to write into an inline script, carried as payload fields.
    const encodedComponentRegistry = `Type.map([[Type.bitstring("page"), Type.map([[Type.atom("module"), ${encodedModule7}], [Type.atom("struct"), Type.componentStruct({state: Type.map([[Type.atom("count"), Type.integer(7)]])})]])]])`;

    const payloadFor = (pageDigest, bodyText = "page content") => ({
      componentRegistry: encodedComponentRegistry,
      pageDigest: pageDigest,
      pageModule: encodedModule7,
      pageParams: encodedNoParams,
      selfEchoes: "Type.list([])",
      subReceiptAdds: "Type.list([])",
      subReceiptDrops: "Type.list([])",
      tree: treeFor(pageDigest, bodyText),
      type: "page",
    });

    const bundleScript = (pageDigest) =>
      document.head.querySelector(
        `script[src="/hologram/page-${pageDigest}.js"]`,
      );

    // The page a navigation patches against, which on a document load is the render mirrored
    // onto what the server sent.
    const seedCurrentPage = () => {
      Hologram.virtualDocument = Vdom.mirror(
        Renderer.renderTree(
          Renderer.decodeTree(treeFor("current", "current page content")),
        ),
        document.documentElement,
      );
    };

    const removeBundleScripts = () =>
      document.head
        .querySelectorAll("script[src^='/hologram/page-']")
        .forEach((script) => script.remove());

    beforeEach(() => {
      assignedUrls = [];

      assignStub = sinon
        .stub(Hologram, "leaveApp")
        .callsFake((url) => assignedUrls.push(url));

      fetchPageStub = sinon.stub(Client, "fetchPage");
    });

    afterEach(() => {
      Client.fetchPage.restore();
      assignStub.restore();

      // A navigation opens a transition window and only a mount closes it, which these tests
      // never reach - so it is closed here rather than left open for whatever runs next.
      Hologram.domEpoch = 0;
      Hologram.registryEpoch = 0;
    });

    // A page the client cannot ask for is one only the browser can reach.
    it("hands a redirect target that names no page to the browser", async () => {
      await Hologram.loadNewPage("/clicked", {
        to: "https://example.com/x",
        type: "redirect",
      });

      assert.deepStrictEqual(assignedUrls, ["https://example.com/x"]);
      sinon.assert.notCalled(fetchPageStub);
    });

    it("follows a redirect by asking for the page it names", async () => {
      fetchPageStub.callsFake((toParam, _onSuccess, _onNotPage) => {
        assert.equal(
          toParam.data[0].value,
          "Elixir.Hologram.Test.Fixtures.Module7",
        );
        return null;
      });

      await Hologram.loadNewPage("/clicked", redirectTo("/target"));

      sinon.assert.calledOnce(fetchPageStub);
    });

    // A redirect can point at a page that redirects again, and a cycle would otherwise fetch
    // forever without anything to show for it.
    it("gives up after too many redirect hops", async () => {
      fetchPageStub.callsFake((_toParam, onSuccess, _onNotPage) =>
        onSuccess(redirectTo("/loop")),
      );

      let thrownError = null;

      try {
        await Hologram.loadNewPage("/clicked", redirectTo("/loop"));
      } catch (error) {
        thrownError = error;
      }

      assert.match(thrownError?.message ?? "", /Too many redirects/);
      assert.isAtMost(fetchPageStub.callCount, 10);
    });

    // The page the server described is patched in as soon as it arrives, so it is on screen a
    // round trip after it was asked for rather than a round trip plus a bundle plus a render.
    describe("showing the page the server described", () => {
      let patchStub;

      beforeEach(() => {
        // jsdom has no rAF, and the patch runs inside one. Running it now keeps the test reading
        // top to bottom.
        window.requestAnimationFrame = (callback) => callback();
        seedCurrentPage();
      });

      afterEach(() => {
        delete window.requestAnimationFrame;
        delete globalThis.Hologram.pageScriptLoaded;
        Hologram.virtualDocument = null;

        patchStub?.restore();
        patchStub = null;

        removeBundleScripts();
      });

      // The point of carrying the state beside the render: it is readable without any script
      // having run, so it no longer depends on the patch inserting one and the browser executing
      // it. No mount data script exists in this tree at all.
      it("makes the page's mount data readable before the patch", async () => {
        delete globalThis.Hologram.pageMountData;
        globalThis.Hologram.pageScriptLoaded = true;

        await Hologram.loadNewPage("/target", payloadFor("mount-data"));

        // Nothing defined the carrier, so the mount can only have read the payload.
        assert.isUndefined(globalThis.Hologram.pageMountData);
        assert.notInclude(document.head.innerHTML, "pageMountData");
      });

      // That the mount then consumes it is a feature test's job - the mount is not reachable from
      // here, since it needs either the destination's code already registered or its bundle to
      // announce itself. What is provable here is that the payload's fields are decoded during
      // the swap: a field that cannot be evaluated fails it.
      it("decodes the payload's mount data during the swap", async () => {
        globalThis.Hologram.pageScriptLoaded = true;

        const payload = {
          ...payloadFor("bad-registry"),
          componentRegistry: "Type.map([[[",
        };

        let thrown = null;

        try {
          await Hologram.loadNewPage("/target", payload);
        } catch (error) {
          thrown = error;
        }

        assert.isNotNull(thrown);
      });

      // The property the whole feature rests on: what the server described is on screen while the
      // page's own code is still in flight.
      it("puts the page on screen before its bundle has run", async () => {
        globalThis.Hologram.pageScriptLoaded = true;

        await Hologram.loadNewPage("/target", payloadFor("aaa", "new content"));

        assert.include(document.body.textContent, "new content");
        assert.isFalse(globalThis.Hologram.pageScriptLoaded);
      });

      // The swap advances the epoch of what is displayed while the registry's epoch stays put -
      // the gap between the two is what marks the transition window until the mount closes it.
      it("advances the epoch of what is on screen ahead of the registry", async () => {
        assert.equal(Hologram.domEpoch, 0);
        assert.equal(Hologram.registryEpoch, 0);

        await Hologram.loadNewPage("/target", payloadFor("epoch1"));

        assert.equal(Hologram.domEpoch, 1);
        assert.equal(Hologram.registryEpoch, 0);
      });

      // The destination is on screen from the patch onward, but its mount waits on the bundle -
      // so a dispatch that fires in between would run against a registry that is still the
      // previous page's, and render that page over the destination.
      it("drops a pending action before the destination is patched in", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        try {
          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("stale"),
              params: Type.map(),
              target: cid1,
              delay: Type.integer(100),
            }),
          );

          await Hologram.loadNewPage("/target", payloadFor("ddd"));

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
        }
      });

      // Everything the destination arms carries the destination's epoch, and the registry cannot
      // answer for that page until it mounts - so it waits rather than running against the page
      // being left, and rather than being swept.
      it("holds what the destination arms until the mount", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target", payloadFor("fff"));

          const action = Type.actionStruct({
            name: Type.atom("armed_by_destination"),
            params: Type.map(),
            target: cid1,
          });

          Hologram.scheduleAction(action, Hologram.domEpoch);
          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);

          // A held action and a dropped one both leave executeAction uncalled. The absence of the
          // warning is what says this one is waiting rather than gone.
          sinon.assert.notCalled(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // An action that reasoned about the registry - a server push, a command's reply - was right
      // about the page it saw, but that page is being left, so it goes no further.
      it("drops what reasoned about the page being left", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target", payloadFor("iii"));

          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("armed_by_the_registry"),
              params: Type.map(),
              target: cid1,
            }),
          );

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledOnce(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // The widest window a dispatch can outlive its page in is the one its own delay gives it -
      // the timer survives the navigation and only meets the settle rule once the delay is up.
      it("drops an action whose delay outlives the page that armed it", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("armed_before_the_swap"),
              params: Type.map(),
              target: cid1,
              delay: Type.integer(3000),
            }),
          );

          clock.tick(1000);
          sinon.assert.notCalled(executeActionStub);

          await Hologram.loadNewPage("/target", payloadFor("jjj"));

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledOnce(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // Nothing about the rule is per-action: everything the page being left had in flight goes,
      // whatever delay each was given.
      it("drops every action the page being left had pending", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        const pending = (name, delay) =>
          Type.actionStruct({
            name: Type.atom(name),
            params: Type.map(),
            target: cid1,
            delay: Type.integer(delay),
          });

        try {
          Hologram.scheduleAction(pending("pending_immediate", 0));
          Hologram.scheduleAction(pending("pending_100ms", 100));
          Hologram.scheduleAction(pending("pending_300ms", 300));

          await Hologram.loadNewPage("/target", payloadFor("kkk"));

          clock.tick(1000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledThrice(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // The destination's script runs during the patch, which for a page whose bundle is still
      // being fetched is a whole fetch before the mount - so dispatching then would resolve the
      // target against the page being left rather than against the page that carries the script.
      it("holds an action the destination's script dispatches before the mount", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target", payloadFor("ggg"));

          Hologram.dispatchAction("dispatched_by_script", "page", {value: 99});

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);

          // A held action and a dropped one both leave executeAction uncalled. The absence of the
          // warning is what says the script's dispatch is waiting for its page rather than having
          // been resolved against the page being left.
          sinon.assert.notCalled(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      it("fetches the bundle of a page this client has not run before", async () => {
        await Hologram.loadNewPage("/target", payloadFor("bbb"));

        assert.isNotNull(bundleScript("bbb"));
      });

      // A script is keyed by the source it loads, so a bundle already in the document would be
      // adopted rather than run, and one only in memory would run a second time. Neither can
      // announce the mount, so the patch never carries the bundle.
      it("keeps the page's bundle out of the patch", async () => {
        patchStub = sinon
          .stub(Vdom, "patchVirtualDocument")
          .returns(Hologram.virtualDocument);

        await Hologram.loadNewPage("/target", payloadFor("ccc"));

        const patchedHead = patchStub.firstCall.args[1].children.find(
          (child) => child?.sel === "head",
        );

        assert.deepStrictEqual(patchedHead.children, []);
      });
    });

    // A bundle that never loads would otherwise end the navigation in silence: nothing dispatches
    // hologram:pageScriptLoaded, so the mount never runs and the page on screen stays put.
    describe("page bundle that fails to load", () => {
      beforeEach(() => {
        window.requestAnimationFrame = (callback) => callback();
        seedCurrentPage();
      });

      afterEach(() => {
        delete window.requestAnimationFrame;
        delete globalThis.Hologram.pageScriptLoaded;
        Hologram.virtualDocument = null;
        removeBundleScripts();
      });

      it("raises rather than leaving the navigation unfinished", async () => {
        await Hologram.loadNewPage("/target-eee", payloadFor("eee"));

        const script = bundleScript("eee");

        assert.isNotNull(script);

        assert.throws(
          () => script.onerror(),
          HologramRuntimeError,
          "Failed to load page bundle: /hologram/page-eee.js",
        );
      });

      // The mount that would have answered for this page is never going to run, so nothing it
      // carries can be resolved. Holding would swallow every later dispatch for the rest of the
      // session, so the epoch is recorded dead and what belongs to it is dropped - and said.
      it("drops a dispatch once the mount can no longer happen", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target-hhh", payloadFor("hhh"));

          assert.throws(
            () => bundleScript("hhh").onerror(),
            HologramRuntimeError,
            "Failed to load page bundle: /hologram/page-hhh.js",
          );

          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("after_bundle_failure"),
              params: Type.map(),
              target: cid1,
            }),
            Hologram.domEpoch,
          );

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledOnce(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });
    });
  });

  describe("handlePrefetchPageNotPage()", () => {
    let leaveAppStub;

    beforeEach(() => {
      leaveAppStub = sinon.stub(Hologram, "leaveApp");
    });

    afterEach(() => leaveAppStub.restore());

    it("leaves the app when navigate has already been confirmed", () => {
      Hologram.prefetchedPages = new Map([
        [
          "dummy_map_key",
          {
            isNavigateConfirmed: true,
            isPage: true,
            pagePath: "/my-page-path",
            payload: null,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.handlePrefetchPageNotPage("dummy_map_key");

      assert.equal(Hologram.prefetchedPages.size, 0);
      sinon.assert.calledOnceWithExactly(leaveAppStub, "/my-page-path");
    });

    // Before the click, the answer is only remembered: leaving the app on hover would take the
    // user somewhere they have not asked to go.
    it("marks the entry when navigate hasn't been confirmed", () => {
      const mapKey = "dummy_map_key";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            isNavigateConfirmed: false,
            isPage: true,
            pagePath: "/my-page-path",
            payload: null,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.handlePrefetchPageNotPage(mapKey);

      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isFalse(Hologram.prefetchedPages.get(mapKey).isPage);
      sinon.assert.notCalled(leaveAppStub);
    });

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.handlePrefetchPageNotPage("dummy_map_key");

      assert.equal(Hologram.prefetchedPages.size, 0);
      sinon.assert.notCalled(leaveAppStub);
    });
  });

  describe("handlePrefetchPageSuccess()", () => {
    let loadNewPageStub;

    beforeEach(() => {
      loadNewPageStub = sinon
        .stub(Hologram, "loadNewPage")
        .callsFake((_pagePath, _payload) => null);
    });

    afterEach(() => Hologram.loadNewPage.restore());

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.handlePrefetchPageSuccess("dummy_map_key", {type: "page"});

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.notCalled(loadNewPageStub);
    });

    it("navigate has been confirmed", () => {
      Hologram.prefetchedPages = new Map([
        [
          "dummy_map_key",
          {
            payload: null,
            isNavigateConfirmed: true,
            pagePath: "/my-page-path",
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.handlePrefetchPageSuccess("dummy_map_key", {type: "page"});

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(loadNewPageStub, "/my-page-path", {
        type: "page",
      });
    });

    it("navigate hasn't been confirmed", () => {
      const mapKey = "dummy_map_key";
      const timestamp = Date.now();

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            payload: null,
            isNavigateConfirmed: false,
            pagePath: "/my-page-path",
            timestamp: timestamp,
          },
        ],
      ]);

      Hologram.handlePrefetchPageSuccess(mapKey, {type: "page"});

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(mapValue, {
        payload: {type: "page"},
        isNavigateConfirmed: false,
        pagePath: "/my-page-path",
        timestamp: timestamp,
      });

      sinon.assert.notCalled(loadNewPageStub);
    });
  });

  describe("handleUncaughtError()", () => {
    let overlayShowStub;

    const boxedError = () =>
      new HologramBoxedError(Type.errorStruct("MyError", "my message"));

    beforeEach(() => {
      CallStack.reset();
      overlayShowStub = sinon.stub(UncaughtErrorOverlay, "show");
      globalThis.Hologram.config.errorOverlay = false;
    });

    afterEach(() => {
      overlayShowStub.restore();
      globalThis.Hologram.config.errorOverlay = false;
    });

    // The overlay reads the frames and the message off the error itself, so
    // it is handed the error rather than the report rendered from it.
    it("renders the error in the page when the overlay is enabled", () => {
      globalThis.Hologram.config.errorOverlay = true;

      const error = boxedError();

      Hologram.handleUncaughtError(error);

      sinon.assert.calledOnceWithExactly(overlayShowStub, error);
    });

    it("keeps the error out of the page when the overlay is disabled", () => {
      Hologram.handleUncaughtError(boxedError());

      sinon.assert.notCalled(overlayShowStub);
    });

    it("records the error for the feature test helpers", () => {
      Hologram.handleUncaughtError(boxedError());

      assert.deepStrictEqual(GlobalRegistry.get("lastBoxedError"), {
        module: "MyError",
        message: "my message",
      });
    });

    // Deriving here a second time would fault the same way the first one did,
    // leaving the error unreported - the very thing the reader needs to see.
    it("records an error that failed to derive its message, naming the fault", () => {
      const normalizeErrorStub = sinon
        .stub(Interpreter, "normalizeError")
        .callsFake(() => {
          throw new TypeError("my fault");
        });

      const error = new HologramBoxedError(Type.atom("badarg"));

      normalizeErrorStub.restore();

      Hologram.handleUncaughtError(error);

      assert.deepStrictEqual(GlobalRegistry.get("lastBoxedError"), {
        module: "error",
        message: ":badarg (message derivation failed: my fault)",
      });
    });

    it("ignores an error raised outside the runtime", () => {
      globalThis.Hologram.config.errorOverlay = true;

      const error = new Error("my message");

      Hologram.handleUncaughtError(error);

      assert.equal(error.message, "my message");
      sinon.assert.notCalled(overlayShowStub);
    });
  });

  describe("queueActionsFromServerInits()", () => {
    const cid1 = Type.bitstring("component_1");
    const cid2 = Type.bitstring("component_2");
    const cid3 = Type.bitstring("component_3");
    const cid4 = Type.bitstring("component_4");
    const cid5 = Type.bitstring("component_5");
    const cid6 = Type.bitstring("component_6");

    const action1 = Type.actionStruct({
      name: Type.atom("action_1"),
      params: Type.map(),
      target: Type.bitstring("my_target_1"),
    });

    const action2 = Type.actionStruct({
      name: Type.atom("action_2"),
      params: Type.map([[Type.atom("my_param"), Type.integer(42)]]),
      target: Type.bitstring("my_target_2"),
    });

    const action3 = Type.actionStruct({
      name: Type.atom("action_3"),
      params: Type.map(),
      target: Type.nil(),
    });

    const action6 = Type.actionStruct({
      name: Type.atom("action_6"),
      params: Type.map(),
      target: Type.bitstring("my_target_6"),
    });

    let entry1, entry2, entry3, entry4, entry5, entry6;

    beforeEach(() => {
      ComponentRegistry.clear();
      InitActionQueue.dequeueAll();

      entry1 = Type.map([
        [Type.atom("module"), Type.alias("Module1")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action1})],
      ]);

      entry2 = Type.map([
        [Type.atom("module"), Type.alias("Module2")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action2})],
      ]);

      entry3 = Type.map([
        [Type.atom("module"), Type.alias("Module3")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action3})],
      ]);

      entry4 = Type.map([
        [Type.atom("module"), Type.alias("Module4")],
        [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
      ]);

      entry5 = Type.map([
        [Type.atom("module"), Type.alias("Module5")],
        [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
      ]);

      entry6 = Type.map([
        [Type.atom("module"), Type.alias("Module6")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action6})],
      ]);
    });

    it("queues actions from all components that have next_action set", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, entry1],
        [cid2, entry2],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = InitActionQueue.dequeueAll();
      assert.equal(queuedActions.length, 2);

      assert.deepStrictEqual(queuedActions[0], action1);
      assert.deepStrictEqual(queuedActions[1], action2);
    });

    it("skips components that don't have next_action set", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, entry1],
        [cid4, entry4],
        [cid2, entry2],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = InitActionQueue.dequeueAll();
      assert.equal(queuedActions.length, 2);

      assert.deepStrictEqual(queuedActions[0], action1);
      assert.deepStrictEqual(queuedActions[1], action2);
    });

    it("handles empty component registry", () => {
      Hologram.queueActionsFromServerInits();

      const queuedActions = InitActionQueue.dequeueAll();
      assert.equal(queuedActions.length, 0);
    });

    it("handles component registry with only components without next_action", () => {
      ComponentRegistry.entries = Type.map([
        [cid4, entry4],
        [cid5, entry5],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = InitActionQueue.dequeueAll();
      assert.equal(queuedActions.length, 0);
    });

    it("preserves existing target when action already has one", () => {
      ComponentRegistry.entries = Type.map([[cid1, entry1]]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = InitActionQueue.dequeueAll();

      // Should not modify the action
      assert.deepStrictEqual(queuedActions[0], action1);
    });

    it("adds component ID as target when action has nil target", () => {
      ComponentRegistry.entries = Type.map([[cid3, entry3]]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = InitActionQueue.dequeueAll();

      const expectedAction = Erlang_Maps["put/3"](
        Type.atom("target"),
        cid3,
        action3,
      );

      assert.deepStrictEqual(queuedActions[0], expectedAction);
    });

    it("processes components in the order they appear in the registry", () => {
      ComponentRegistry.entries = Type.map([
        [cid2, entry2],
        [cid6, entry6],
        [cid1, entry1],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = InitActionQueue.dequeueAll();
      assert.equal(queuedActions.length, 3);

      assert.deepStrictEqual(queuedActions[0], action2);
      assert.deepStrictEqual(queuedActions[1], action6);
      assert.deepStrictEqual(queuedActions[2], action1);
    });

    it("clears next_action from the component struct in the registry after queueing", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, entry1],
        [cid3, entry3],
      ]);

      Hologram.queueActionsFromServerInits();

      const struct1 = ComponentRegistry.getComponentStruct(cid1);
      const struct3 = ComponentRegistry.getComponentStruct(cid3);

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("next_action"), struct1),
        Type.nil(),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("next_action"), struct3),
        Type.nil(),
      );
    });
  });

  describe("queueSelfEchoes()", () => {
    const action1 = Type.actionStruct({
      name: Type.atom("self_echo_a"),
      params: Type.map(),
      target: Type.bitstring("page"),
    });

    const action2 = Type.actionStruct({
      name: Type.atom("self_echo_b"),
      params: Type.map([[Type.atom("text"), Type.bitstring("hi")]]),
      target: Type.bitstring("page"),
    });

    beforeEach(() => {
      InitActionQueue.dequeueAll();
    });

    it("does not enqueue anything when the list is empty", () => {
      Hologram.queueSelfEchoes(Type.list([]));

      assert.deepStrictEqual(InitActionQueue.dequeueAll(), []);
    });

    it("enqueues each action in order", () => {
      Hologram.queueSelfEchoes(Type.list([action1, action2]));

      assert.deepStrictEqual(InitActionQueue.dequeueAll(), [action1, action2]);
    });
  });

  describe("render()", () => {
    afterEach(() => {
      Hologram.virtualDocument = null;
      Renderer.listenerBindings = [];
      sinon.restore();
    });

    it("reconciles the global and resolved observer bindings collected during the render", () => {
      const listenerBindings = [
        {target: window, eventName: "keydown", handler: () => {}},
      ];

      const reachBinding = {
        target: {},
        key: "scroll-edge:bottom",
        attach: () => {},
        handler: () => {},
      };

      // renderPage() collects the page's <window>/<document> bindings into Renderer.listenerBindings.
      sinon.stub(Renderer, "renderPage").callsFake(() => {
        Renderer.listenerBindings = listenerBindings;
        return {sel: "html", data: {}, children: []};
      });

      // Observer bindings are resolved from their patched elements right before reconciliation.
      sinon.stub(Renderer, "resolveReachBindings").returns([reachBinding]);

      sinon.stub(Vdom, "patchVirtualDocument");
      const reconcileStub = sinon.stub(EventListenerRegistry, "reconcile");
      const recheckStub = sinon.stub(EventListeners, "recheckScrollEdges");

      Hologram.render();

      sinon.assert.calledOnceWithExactly(reconcileStub, [
        ...listenerBindings,
        reachBinding,
      ]);

      // Reach listeners persist, so each is rechecked after reconcile to re-sync and auto-fill.
      sinon.assert.calledOnce(recheckStub);
      sinon.assert.callOrder(reconcileStub, recheckStub);
    });

    // A full document load has no previous render to diff against, only the page the server sent,
    // so the old side is this render mirrored onto it. Reading the page into a vdom of its own
    // instead would describe it in terms the render never uses, and every node would be rebuilt.
    it("seeds the first render by mirroring it onto the page the server sent", () => {
      const renderedVirtualDocument = {sel: "html", data: {}, children: []};
      const mirroredVirtualDocument = {sel: "html", data: {}, children: []};

      sinon.stub(Renderer, "renderPage").returns(renderedVirtualDocument);
      const mirrorStub = sinon
        .stub(Vdom, "mirror")
        .returns(mirroredVirtualDocument);
      const patchStub = sinon.stub(Vdom, "patchVirtualDocument");

      Hologram.virtualDocument = null;

      Hologram.render();

      sinon.assert.calledOnceWithExactly(
        mirrorStub,
        renderedVirtualDocument,
        document.documentElement,
      );

      sinon.assert.calledOnceWithExactly(
        patchStub,
        mirroredVirtualDocument,
        renderedVirtualDocument,
      );
    });

    it("leaves a render that has a previous one to diff against alone", () => {
      const previousVirtualDocument = {sel: "html", data: {}, children: []};
      const renderedVirtualDocument = {sel: "html", data: {}, children: []};

      sinon.stub(Renderer, "renderPage").returns(renderedVirtualDocument);
      const mirrorStub = sinon.stub(Vdom, "mirror");
      const patchStub = sinon.stub(Vdom, "patchVirtualDocument");

      Hologram.virtualDocument = previousVirtualDocument;

      Hologram.render();

      sinon.assert.notCalled(mirrorStub);

      sinon.assert.calledOnceWithExactly(
        patchStub,
        previousVirtualDocument,
        renderedVirtualDocument,
      );
    });
  });

  describe("scheduleAction()", () => {
    let clock, executeActionStub;

    const action1 = Type.actionStruct({
      name: Type.atom("test_action"),
      params: Type.map(),
      target: cid1,
    });

    beforeEach(() => {
      clock = sinon.useFakeTimers();

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);
    });

    afterEach(() => {
      clock.restore();
      sinon.restore();
    });

    it("schedules action execution with setTimeout and 0 delay", () => {
      // Before scheduling, executeAction should not have been called
      sinon.assert.notCalled(executeActionStub);

      Hologram.scheduleAction(action1);

      // Action should not execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Advance time by 0ms to trigger setTimeout callback
      clock.tick(0);

      // Now the action should have been executed
      sinon.assert.calledOnceWithExactly(executeActionStub, action1, 0);
    });

    // The ordinary case: nothing is in flight, so the page on screen is the page the registry
    // answers for and the action it carries resolves against it.
    it("executes an action stamped with the current stable epoch", () => {
      Hologram.scheduleAction(action1);
      clock.tick(0);

      sinon.assert.calledOnceWithExactly(executeActionStub, action1, 0);
    });

    // The shape a history restoration leaves behind: the registry has moved on while the page the
    // action came from is still on screen, so the page it was aimed at is already gone.
    it("drops an action stamped below the current epoch", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.registryEpoch = 1;

        Hologram.scheduleAction(action1, 0);
        clock.tick(0);

        sinon.assert.notCalled(executeActionStub);
        sinon.assert.calledOnce(warnStub);
      } finally {
        Hologram.registryEpoch = 0;
        warnStub.restore();
      }
    });

    it("schedules multiple actions independently", () => {
      const action2 = Type.actionStruct({
        name: Type.atom("test_action_2"),
        params: Type.map(),
        target: Type.bitstring("component_2"),
      });

      Hologram.scheduleAction(action1);
      Hologram.scheduleAction(action2);

      // Neither should execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Both should execute after time advancement
      clock.tick(0);

      sinon.assert.calledTwice(executeActionStub);
      sinon.assert.calledWith(executeActionStub.getCall(0), action1, 0);
      sinon.assert.calledWith(executeActionStub.getCall(1), action2, 0);
    });

    it("schedules action execution with custom delay", () => {
      const actionWithDelay = Type.actionStruct({
        name: Type.atom("test_action_with_delay"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(500),
      });

      sinon.assert.notCalled(executeActionStub);

      Hologram.scheduleAction(actionWithDelay);

      // Action should not execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Action should not execute after short delay
      clock.tick(100);
      sinon.assert.notCalled(executeActionStub);

      // Action should execute after specified delay
      clock.tick(400);
      sinon.assert.calledOnceWithExactly(executeActionStub, actionWithDelay, 0);
    });

    it("schedules multiple actions with different delays in correct order", () => {
      const actionDelayed100 = Type.actionStruct({
        name: Type.atom("action_100ms"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(100),
      });

      const actionDelayed300 = Type.actionStruct({
        name: Type.atom("action_300ms"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(300),
      });

      Hologram.scheduleAction(actionDelayed300);
      Hologram.scheduleAction(actionDelayed100);

      // Neither should execute immediately
      sinon.assert.notCalled(executeActionStub);

      // After 100ms, only the first action should execute
      clock.tick(100);
      sinon.assert.calledOnceWithExactly(
        executeActionStub,
        actionDelayed100,
        0,
      );

      // After another 200ms (total 300ms), the second action should execute
      clock.tick(200);
      sinon.assert.calledTwice(executeActionStub);
      sinon.assert.calledWith(
        executeActionStub.getCall(1),
        actionDelayed300,
        0,
      );
    });

    it("handles action with zero delay same as no delay specified", () => {
      const actionZeroDelay = Type.actionStruct({
        name: Type.atom("test_action_zero_delay"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(0),
      });

      Hologram.scheduleAction(actionZeroDelay);

      // Action should not execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Action should execute after 0ms timeout
      clock.tick(0);
      sinon.assert.calledOnceWithExactly(executeActionStub, actionZeroDelay, 0);
    });
  });
});
