"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  registerWebApis,
  sinon,
  UUID_REGEX,
} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Config from "../../assets/js/config.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import InitActionQueue from "../../assets/js/init_action_queue.mjs";
import Type from "../../assets/js/type.mjs";

import {defineModule7Fixture} from "./support/fixtures/hologram/module_7.mjs";

defineGlobalErlangAndElixirModules();
registerWebApis();
defineModule7Fixture();

const cid1 = Type.bitstring("my_component_1");
const module7 = Type.alias("Hologram.Test.Fixtures.Module7");

describe("Hologram", () => {
  describe("executeLoadPrefetchedPageAction()", () => {
    let eventTargetNode, loadNewPageStub;

    const html = "my_html";

    const loadPrefetchedPageAction = Type.actionStruct({
      name: Type.atom("__load_prefetched_page__"),
      params: Type.map([[Type.atom("to"), module7]]),
      target: cid1,
    });

    const pagePath = "/hologram-test-fixtures-module7";

    beforeEach(() => {
      loadNewPageStub = sinon
        .stub(Hologram, "loadNewPage")
        .callsFake((_pagePath, _html) => null);

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
            html: null,
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
        html: null,
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
            html: html,
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

      sinon.assert.calledOnceWithExactly(loadNewPageStub, pagePath, html);
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
    let clientFetchPageStub,
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

      clientFetchPageStub = sinon
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
        html: null,
        isNavigateConfirmed: false,
        pagePath: pagePath,
        timestamp: mapValue.timestamp,
      });

      assert.isAtMost(Math.abs(Date.now() - mapValue.timestamp), 100);

      sinon.assert.calledOnceWithExactly(
        clientFetchPageStub,
        module7,
        successCallbacks[0],
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
        html: null,
        isNavigateConfirmed: false,
        pagePath: pagePath,
        timestamp: mapValue.timestamp,
      });

      assert.isAtMost(Math.abs(Date.now() - mapValue.timestamp), 100);

      sinon.assert.calledOnceWithExactly(
        clientFetchPageStub,
        module7,
        successCallbacks[0],
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

      sinon.assert.notCalled(clientFetchPageStub);
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
      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

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

      sinon.assert.calledOnceWithExactly(executeActionStub, expectedAction);
      sinon.assert.notCalled(scheduleActionStub);
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

      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        delayedActionSpecDom,
        defaultTarget,
      );

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

      sinon.assert.calledOnceWithExactly(scheduleActionStub, expectedAction);
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

      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

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

      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

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

      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        commandSpecDom,
        defaultTarget,
      );

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
  });

  describe("handlePrefetchPageSuccess()", () => {
    let loadNewPageStub;

    beforeEach(() => {
      loadNewPageStub = sinon
        .stub(Hologram, "loadNewPage")
        .callsFake((_pagePath, _html) => null);
    });

    afterEach(() => Hologram.loadNewPage.restore());

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.handlePrefetchPageSuccess("dummy_map_key", "my_html");

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
            html: null,
            isNavigateConfirmed: true,
            pagePath: "/my-page-path",
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.handlePrefetchPageSuccess("dummy_map_key", "my_html");

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(
        loadNewPageStub,
        "/my-page-path",
        "my_html",
      );
    });

    it("navigate hasn't been confirmed", () => {
      const mapKey = "dummy_map_key";
      const timestamp = Date.now();

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            html: null,
            isNavigateConfirmed: false,
            pagePath: "/my-page-path",
            timestamp: timestamp,
          },
        ],
      ]);

      Hologram.handlePrefetchPageSuccess(mapKey, "my_html");

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(mapValue, {
        html: "my_html",
        isNavigateConfirmed: false,
        pagePath: "/my-page-path",
        timestamp: timestamp,
      });

      sinon.assert.notCalled(loadNewPageStub);
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

    const componentStruct1 = Type.componentStruct({
      nextAction: action1,
    });

    const componentStruct2 = Type.componentStruct({
      nextAction: action2,
    });

    const componentStruct3 = Type.componentStruct({
      nextAction: action3,
    });

    const componentStruct4 = Type.componentStruct({
      nextAction: Type.nil(),
    });

    const componentStruct5 = Type.componentStruct({
      nextAction: Type.nil(),
    });

    const componentStruct6 = Type.componentStruct({
      nextAction: action6,
    });

    const entry1 = Type.map([
      [Type.atom("module"), Type.alias("Module1")],
      [Type.atom("struct"), componentStruct1],
    ]);

    const entry2 = Type.map([
      [Type.atom("module"), Type.alias("Module2")],
      [Type.atom("struct"), componentStruct2],
    ]);

    const entry3 = Type.map([
      [Type.atom("module"), Type.alias("Module3")],
      [Type.atom("struct"), componentStruct3],
    ]);

    const entry4 = Type.map([
      [Type.atom("module"), Type.alias("Module4")],
      [Type.atom("struct"), componentStruct4],
    ]);

    const entry5 = Type.map([
      [Type.atom("module"), Type.alias("Module5")],
      [Type.atom("struct"), componentStruct5],
    ]);

    const entry6 = Type.map([
      [Type.atom("module"), Type.alias("Module6")],
      [Type.atom("struct"), componentStruct6],
    ]);

    beforeEach(() => {
      ComponentRegistry.clear();
      InitActionQueue.dequeueAll();
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
      sinon.assert.calledOnceWithExactly(executeActionStub, action1);
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
      sinon.assert.calledWith(executeActionStub.getCall(0), action1);
      sinon.assert.calledWith(executeActionStub.getCall(1), action2);
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
      sinon.assert.calledOnceWithExactly(executeActionStub, actionWithDelay);
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
      sinon.assert.calledOnceWithExactly(executeActionStub, actionDelayed100);

      // After another 200ms (total 300ms), the second action should execute
      clock.tick(200);
      sinon.assert.calledTwice(executeActionStub);
      sinon.assert.calledWith(executeActionStub.getCall(1), actionDelayed300);
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
      sinon.assert.calledOnceWithExactly(executeActionStub, actionZeroDelay);
    });
  });
});
