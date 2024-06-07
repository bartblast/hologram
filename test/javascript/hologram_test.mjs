"use strict";

import {
  assert,
  commandQueueItemFixture,
  componentRegistryEntryFixture,
  defineGlobalErlangAndElixirModules,
  registerWebApis,
  sinon,
  UUID_REGEX,
} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import CommandQueue from "../../assets/js/command_queue.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Config from "../../assets/js/config.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Type from "../../assets/js/type.mjs";

import {toVNode} from "../../assets/node_modules/snabbdom/build/index.js";
import vnodeToHtml from "../../assets/node_modules/snabbdom-to-html/index.js";

import {defineModule1Fixture} from "./support/fixtures/hologram/module_1.mjs";
import {defineModule2Fixture} from "./support/fixtures/hologram/module_2.mjs";
import {defineModule3Fixture} from "./support/fixtures/hologram/module_3.mjs";
import {defineModule4Fixture} from "./support/fixtures/hologram/module_4.mjs";
import {defineModule5Fixture} from "./support/fixtures/hologram/module_5.mjs";
import {defineModule6Fixture} from "./support/fixtures/hologram/module_6.mjs";
import {defineModule7Fixture} from "./support/fixtures/hologram/module_7.mjs";
import {defineModule8Fixture} from "./support/fixtures/hologram/module_8.mjs";
import {defineModule9Fixture} from "./support/fixtures/hologram/module_9.mjs";

defineGlobalErlangAndElixirModules();
registerWebApis();

const cid1 = Type.bitstring("my_component_1");
const cid2 = Type.bitstring("my_component_2");

const module1 = Type.alias("Module1");
const module2 = Type.alias("Module2");
const module3 = Type.alias("Module3");
const module4 = Type.alias("Module4");
const module5 = Type.alias("Module5");
const module6 = Type.alias("Module6");
const module7 = Type.alias("Hologram.Module7");
const module8 = Type.alias("Hologram.Module8");
const module9 = Type.alias("Hologram.Module9");

describe("Hologram", () => {
  before(() => {
    defineModule1Fixture();
    defineModule2Fixture();
    defineModule3Fixture();
    defineModule4Fixture();
    defineModule5Fixture();
    defineModule6Fixture();
    defineModule7Fixture();
    defineModule8Fixture();
    defineModule9Fixture();
  });

  describe("executeAction()", () => {
    let commandQueueProcessStub, navigateToPageStub, renderStub;

    beforeEach(() => {
      CommandQueue.items = [];
      commandQueueProcessStub = sinon
        .stub(CommandQueue, "process")
        .callsFake(() => null);

      navigateToPageStub = sinon
        .stub(Hologram, "navigateToPage")
        .callsFake(() => null);

      renderStub = sinon.stub(Hologram, "render").callsFake(() => null);
    });

    afterEach(() => {
      CommandQueue.process.restore();
      Hologram.navigateToPage.restore();
      Hologram.render.restore();
    });

    it("without next action or next command", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module1})],
      ]);

      const action = Type.actionStruct({
        name: Type.atom("my_action_1"),
        params: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.integer(1)],
              [Type.atom("page_y"), Type.integer(2)],
            ]),
          ],
        ]),
        target: cid1,
      });

      Hologram.executeAction(action);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid1,
            componentRegistryEntryFixture({
              module: module1,
              emittedContext: Type.map([
                [
                  Type.atom("event"),
                  Type.map([
                    [Type.atom("page_x"), Type.integer(1)],
                    [Type.atom("page_y"), Type.integer(2)],
                  ]),
                ],
              ]),
              state: Type.map([[Type.atom("x"), Type.integer(4)]]),
            }),
          ],
        ]),
      );

      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.calledOnce(renderStub);

      assert.equal(CommandQueue.size(), 0);
    });

    it("with next action having target specified", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module2})],
        [cid2, componentRegistryEntryFixture({module: module6})],
      ]);

      const action = Type.actionStruct({
        name: Type.atom("my_action_2"),
        params: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.integer(1)],
              [Type.atom("page_y"), Type.integer(2)],
            ]),
          ],
        ]),
        target: cid1,
      });

      Hologram.executeAction(action);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid1,
            componentRegistryEntryFixture({
              module: module2,
              emittedContext: Type.map([
                [
                  Type.atom("event"),
                  Type.map([
                    [Type.atom("page_x"), Type.integer(1)],
                    [Type.atom("page_y"), Type.integer(2)],
                  ]),
                ],
              ]),
              state: Type.map([[Type.atom("x"), Type.integer(5)]]),
            }),
          ],
          [
            cid2,
            componentRegistryEntryFixture({
              module: module6,
              emittedContext: Type.map([
                [Type.atom("my_context"), Type.integer(6)],
              ]),
              state: Type.map([[Type.atom("y"), Type.integer(36)]]),
            }),
          ],
        ]),
      );

      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.calledOnce(renderStub);

      assert.equal(CommandQueue.size(), 0);
    });

    it("with next action not having target specified", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module3})],
      ]);

      const action = Type.actionStruct({
        name: Type.atom("my_action_3a"),
        params: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.integer(1)],
              [Type.atom("page_y"), Type.integer(2)],
            ]),
          ],
        ]),
        target: cid1,
      });

      Hologram.executeAction(action);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid1,
            componentRegistryEntryFixture({
              module: module3,
              emittedContext: Type.map([
                [
                  Type.atom("event"),
                  Type.map([
                    [Type.atom("page_x"), Type.integer(1)],
                    [Type.atom("page_y"), Type.integer(2)],
                  ]),
                ],
                [Type.atom("my_context"), Type.integer(3)],
              ]),
              state: Type.map([
                [Type.atom("x"), Type.integer(6)],
                [Type.atom("y"), Type.integer(33)],
              ]),
            }),
          ],
        ]),
      );

      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.calledOnce(renderStub);

      assert.equal(CommandQueue.size(), 0);
    });

    it("with next command having target specified", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module4})],
        [cid2, componentRegistryEntryFixture({module: module5})],
      ]);

      const action = Type.actionStruct({
        name: Type.atom("my_action_4"),
        params: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.integer(1)],
              [Type.atom("page_y"), Type.integer(2)],
            ]),
          ],
        ]),
        target: cid1,
      });

      Hologram.executeAction(action);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid1,
            componentRegistryEntryFixture({
              module: module4,
              emittedContext: Type.map([
                [
                  Type.atom("event"),
                  Type.map([
                    [Type.atom("page_x"), Type.integer(1)],
                    [Type.atom("page_y"), Type.integer(2)],
                  ]),
                ],
              ]),
              state: Type.map([[Type.atom("x"), Type.integer(7)]]),
            }),
          ],
          [cid2, componentRegistryEntryFixture({module: module5})],
        ]),
      );

      sinon.assert.calledOnce(commandQueueProcessStub);
      sinon.assert.calledOnce(renderStub);

      assert.equal(CommandQueue.size(), 1);

      const enqueuedItem = CommandQueue.getNextPending();

      assert.deepStrictEqual(
        enqueuedItem,
        commandQueueItemFixture({
          id: enqueuedItem.id,
          module: module5,
          name: Type.atom("my_command_5"),
          params: Type.map([
            [Type.atom("c"), Type.integer(10)],
            [Type.atom("d"), Type.integer(20)],
          ]),
          status: "pending",
          target: cid2,
        }),
      );
    });

    it("with next command not having target specified", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module5})],
      ]);

      const action = Type.actionStruct({
        name: Type.atom("my_action_5"),
        params: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.integer(1)],
              [Type.atom("page_y"), Type.integer(2)],
            ]),
          ],
        ]),
        target: cid1,
      });

      Hologram.executeAction(action);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid1,
            componentRegistryEntryFixture({
              module: module5,
              emittedContext: Type.map([
                [
                  Type.atom("event"),
                  Type.map([
                    [Type.atom("page_x"), Type.integer(1)],
                    [Type.atom("page_y"), Type.integer(2)],
                  ]),
                ],
              ]),
              state: Type.map([[Type.atom("x"), Type.integer(8)]]),
            }),
          ],
        ]),
      );

      sinon.assert.calledOnce(commandQueueProcessStub);
      sinon.assert.calledOnce(renderStub);

      assert.equal(CommandQueue.size(), 1);

      const enqueuedItem = CommandQueue.getNextPending();

      assert.deepStrictEqual(
        enqueuedItem,
        commandQueueItemFixture({
          id: enqueuedItem.id,
          failCount: 0,
          module: module5,
          name: Type.atom("my_command_6"),
          params: Type.map([
            [Type.atom("c"), Type.integer(10)],
            [Type.atom("d"), Type.integer(20)],
          ]),
          status: "pending",
          target: cid1,
        }),
      );
    });

    it("with next page", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module8})],
      ]);

      const action = Type.actionStruct({
        name: Type.atom("my_action_8"),
        params: Type.map(),
        target: cid1,
      });

      Hologram.executeAction(action);

      sinon.assert.calledOnceWithExactly(
        navigateToPageStub,
        Type.alias("MyPage"),
      );
    });

    it("without next page", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module9})],
      ]);

      const action = Type.actionStruct({
        name: Type.atom("my_action_9"),
        params: Type.map(),
        target: cid1,
      });

      Hologram.executeAction(action);

      sinon.assert.notCalled(navigateToPageStub);
    });
  });

  describe("executeNavigateToPrefetchedPageAction()", () => {
    let eventTargetNode, loadPageStub;

    const html = "my_html";

    const navigateToPrefetchedPageAction = Type.actionStruct({
      name: Type.atom("__navigate_to_prefetched_page__"),
      params: Type.map([[Type.atom("to"), module7]]),
      target: cid1,
    });

    const pagePath = "/hologram-test-fixtures-module7";

    beforeEach(() => {
      loadPageStub = sinon
        .stub(Hologram, "loadPage")
        .callsFake((_pagePath, _html) => null);

      eventTargetNode = {id: "dummy_event_target_node"};
    });

    afterEach(() => Hologram.loadPage.restore());

    it("adds a Hologram ID to an event target DOM node that doesn't have one", () => {
      Hologram.executeNavigateToPrefetchedPageAction(
        navigateToPrefetchedPageAction,
        eventTargetNode,
      );

      assert.match(eventTargetNode.__hologramId__, UUID_REGEX);
    });

    it("doesn't add a Hologram ID to an event target DOM node that already has one", () => {
      eventTargetNode.__hologramId__ = "dummy_hologram_id";

      Hologram.executeNavigateToPrefetchedPageAction(
        navigateToPrefetchedPageAction,
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

      Hologram.executeNavigateToPrefetchedPageAction(
        navigateToPrefetchedPageAction,
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

      sinon.assert.notCalled(loadPageStub);
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

      Hologram.executeNavigateToPrefetchedPageAction(
        navigateToPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(loadPageStub, pagePath, html);
    });

    it("is a no-op if there is no prefeteched pages map entry for the given map key", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.executeNavigateToPrefetchedPageAction(
        navigateToPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.notCalled(loadPageStub);
    });
  });

  describe("executePrefetchPageAction()", () => {
    let clientFetchPageStub,
      errorCallbacks,
      eventTargetNode,
      onPrefetchPageErrorStub,
      onPrefetchPageSuccessStub,
      successCallbacks;

    const pagePath = "/hologram-test-fixtures-module7";

    const prefetchPageAction = Type.actionStruct({
      name: Elixir_Hologram_RuntimeSettings["prefetch_page_action_name/0"](),
      params: Type.map([[Type.atom("to"), module7]]),
      target: cid1,
    });

    const resp = "dummy_resp";

    beforeEach(() => {
      successCallbacks = [];
      errorCallbacks = [];

      clientFetchPageStub = sinon
        .stub(Client, "fetchPage")
        .callsFake((_toParam, successCallback, errorCallback) => {
          successCallbacks.push(successCallback);
          errorCallbacks.push(errorCallback);
        });

      onPrefetchPageSuccessStub = sinon
        .stub(Hologram, "onPrefetchPageSuccess")
        .callsFake((_mapKey, _resp) => null);

      onPrefetchPageErrorStub = sinon
        .stub(Hologram, "onPrefetchPageError")
        .callsFake((_mapKey, _resp) => null);

      eventTargetNode = {id: "dummy_event_target_node"};
    });

    afterEach(() => {
      Client.fetchPage.restore();
      Hologram.onPrefetchPageSuccess.restore();
      Hologram.onPrefetchPageError.restore();
    });

    it("adds a Hologram ID to an event target DOM node that doesn't have one", () => {
      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      assert.match(
        eventTargetNode.__hologramId__,
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
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
        errorCallbacks[0],
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        onPrefetchPageSuccessStub,
        mapKey,
        resp,
      );

      assert.equal(errorCallbacks.length, 1);

      errorCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(onPrefetchPageErrorStub, mapKey, resp);
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
        errorCallbacks[0],
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        onPrefetchPageSuccessStub,
        mapKey,
        resp,
      );

      assert.equal(errorCallbacks.length, 1);

      errorCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(onPrefetchPageErrorStub, mapKey, resp);
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
      sinon.assert.notCalled(onPrefetchPageSuccessStub);
      sinon.assert.notCalled(onPrefetchPageErrorStub);
    });
  });

  describe("handleEvent()", () => {
    let commandQueueProcessStub,
      commandQueuePushStub,
      executeActionStub,
      executeNavigateToPrefetchedPageActionStub,
      executePrefetchPageActionStub;

    const actionSpecDom = Type.keywordList([
      [Type.atom("text"), Type.bitstring("my_action")],
    ]);

    const defaultTarget = cid1;
    const eventType = "click";
    const notIgnoredEvent = {
      pageX: 1,
      pageY: 2,
      preventDefault: () => null,
      target: {id: "dummy_node"},
    };

    beforeEach(() => {
      commandQueueProcessStub = sinon
        .stub(CommandQueue, "process")
        .callsFake(() => null);

      commandQueuePushStub = sinon
        .stub(CommandQueue, "push")
        .callsFake((_command) => null);

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);

      executeNavigateToPrefetchedPageActionStub = sinon
        .stub(Hologram, "executeNavigateToPrefetchedPageAction")
        .callsFake((_action, _eventTargetNode) => null);

      executePrefetchPageActionStub = sinon
        .stub(Hologram, "executePrefetchPageAction")
        .callsFake((_action, _eventTargetNode) => null);
    });

    afterEach(() => {
      CommandQueue.process.restore();
      CommandQueue.push.restore();
      Hologram.executeAction.restore();
      Hologram.executeNavigateToPrefetchedPageAction.restore();
      Hologram.executePrefetchPageAction.restore();
    });

    it("event is ignored", () => {
      const ignoredEvent = {
        ctrlKey: true,
        pageX: 1,
        pageY: 2,
        preventDefault: () => null,
      };

      Hologram.handleEvent(
        ignoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(commandQueuePushStub);
      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeNavigateToPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
    });

    it("regular action", () => {
      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(commandQueuePushStub);
      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.notCalled(executeNavigateToPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        params: Type.map([
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(executeActionStub, expectedAction);
    });

    it("navigate to prefetched page action", () => {
      const actionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.actionStruct({
              name: Type.atom("__navigate_to_prefetched_page__"),
              params: Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
            }),
          ]),
        ],
      ]);

      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(commandQueuePushStub);
      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("__navigate_to_prefetched_page__"),
        params: Type.map([
          [Type.atom("to"), Type.alias("MyPage")],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(
        executeNavigateToPrefetchedPageActionStub,
        expectedAction,
        notIgnoredEvent.target,
      );
    });

    it("prefetch page action", () => {
      const actionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.actionStruct({
              name: Elixir_Hologram_RuntimeSettings[
                "prefetch_page_action_name/0"
              ](),
              params: Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
            }),
          ]),
        ],
      ]);

      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(commandQueuePushStub);
      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeNavigateToPrefetchedPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Elixir_Hologram_RuntimeSettings["prefetch_page_action_name/0"](),
        params: Type.map([
          [Type.atom("to"), Type.alias("MyPage")],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
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
      const commandSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([Type.commandStruct({name: Type.atom("my_command")})]),
        ],
      ]);

      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        commandSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(executeNavigateToPrefetchedPageActionStub);

      const expectedCommand = Type.commandStruct({
        name: Type.atom("my_command"),
        params: Type.map([
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(commandQueuePushStub, expectedCommand);
      sinon.assert.calledOnceWithExactly(commandQueueProcessStub);
    });
  });

  it("loadPage()", () => {
    const historyPushStateStub = sinon
      .stub(history, "pushState")
      .callsFake((_state, _unused, _url) => null);

    const windowScrollToStub = sinon
      .stub(window, "scrollTo")
      .callsFake((_x, _y) => null);

    globalThis.__hologramPageScriptLoaded__ = true;

    const parser = new DOMParser();

    const doc = parser.parseFromString(
      "<DOCTYPE html><html><head></head><body><div></div></body></html>",
      "text/html",
    );

    Hologram.virtualDocument = toVNode(doc.documentElement);

    const pagePath = "/my-page-path";

    const html =
      "<!DOCTYPE html><html><head></head><body><span></span></body></html>";

    Hologram.loadPage(pagePath, html);

    assert.isFalse(globalThis.__hologramPageScriptLoaded__);

    assert.deepStrictEqual(
      vnodeToHtml(Hologram.virtualDocument),
      "<html><head></head><body><span></span></body></html>",
    );

    sinon.assert.calledOnceWithExactly(
      historyPushStateStub,
      null,
      null,
      pagePath,
    );

    sinon.assert.calledOnceWithExactly(windowScrollToStub, 0, 0);

    history.pushState.restore();
    window.scrollTo.restore();
  });

  it("navigateToPage()", () => {
    const successCallbacks = [];
    const errorCallbacks = [];

    const clientFetchPageSub = sinon
      .stub(Client, "fetchPage")
      .callsFake((_toParam, successCallback, errorCallback) => {
        successCallbacks.push(successCallback);
        errorCallbacks.push(errorCallback);
      });

    const loadPageStub = sinon.stub(Hologram, "loadPage").callsFake(() => null);

    Hologram.navigateToPage(module7);

    sinon.assert.calledOnceWithExactly(
      clientFetchPageSub,
      module7,
      successCallbacks[0],
      errorCallbacks[0],
    );

    assert.equal(successCallbacks.length, 1);

    successCallbacks[0]("dummy_resp");

    sinon.assert.calledOnceWithExactly(
      loadPageStub,
      "/hologram-test-fixtures-module7",
      "dummy_resp",
    );

    assert.equal(errorCallbacks.length, 1);

    assert.throw(
      () => errorCallbacks[0]("dummy_resp"),
      HologramRuntimeError,
      "Failed to navigate to page: /hologram-test-fixtures-module7",
    );

    Client.fetchPage.restore();
    Hologram.loadPage.restore();
  });

  describe("onPrefetchPageError()", () => {
    let consoleErrorStub;

    beforeEach(() => {
      consoleErrorStub = sinon
        .stub(globalThis.console, "error")
        .callsFake((_arg1, _arg2) => null);
    });

    afterEach(() => globalThis.console.error.restore());

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.onPrefetchPageError("dummy_map_key", "my_resp");

      sinon.assert.notCalled(consoleErrorStub);
    });

    it("has prefetchedPages map entry", () => {
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

      Hologram.onPrefetchPageError("dummy_map_key", "my_resp");

      sinon.assert.calledOnceWithExactly(
        consoleErrorStub,
        "page prefetch failed:",
        "/my-page-path",
      );
    });
  });

  describe("onPrefetchPageSuccess()", () => {
    let loadPageStub;

    beforeEach(() => {
      loadPageStub = sinon
        .stub(Hologram, "loadPage")
        .callsFake((_pagePath, _html) => null);
    });

    afterEach(() => Hologram.loadPage.restore());

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.onPrefetchPageSuccess("dummy_map_key", "my_html");

      assert.deepStrictEqual(Hologram.prefetchedPages, new Map());
      sinon.assert.notCalled(loadPageStub);
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

      Hologram.onPrefetchPageSuccess("dummy_map_key", "my_html");

      assert.deepStrictEqual(Hologram.prefetchedPages, new Map());

      sinon.assert.calledOnceWithExactly(
        loadPageStub,
        "/my-page-path",
        "my_html",
      );
    });

    it("navigate hasn't been confirmed", () => {
      Hologram.prefetchedPages = new Map([
        [
          "dummy_map_key",
          {
            html: null,
            isNavigateConfirmed: false,
            pagePath: "/my-page-path",
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.onPrefetchPageSuccess("dummy_map_key", "my_html");

      assert.deepStrictEqual(
        Hologram.prefetchedPages,
        new Map([
          [
            "dummy_map_key",
            {
              html: "my_html",
              isNavigateConfirmed: false,
              pagePath: "/my-page-path",
              timestamp: Date.now(),
            },
          ],
        ]),
      );

      sinon.assert.notCalled(loadPageStub);
    });
  });
});
