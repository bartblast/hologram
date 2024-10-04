"use strict";

import {
  assert,
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

defineModule1Fixture();
defineModule2Fixture();
defineModule3Fixture();
defineModule4Fixture();
defineModule5Fixture();
defineModule6Fixture();
defineModule7Fixture();
defineModule8Fixture();
defineModule9Fixture();

const cid1 = Type.bitstring("my_component_1");
const cid2 = Type.bitstring("my_component_2");

const module1 = Type.alias("Hologram.Test.Fixtures.Module1");
const module2 = Type.alias("Hologram.Test.Fixtures.Module2");
const module3 = Type.alias("Hologram.Test.Fixtures.Module3");
const module4 = Type.alias("Hologram.Test.Fixtures.Module4");
const module5 = Type.alias("Hologram.Test.Fixtures.Module5");
const module6 = Type.alias("Hologram.Test.Fixtures.Module6");
const module7 = Type.alias("Hologram.Test.Fixtures.Module7");
const module8 = Type.alias("Hologram.Test.Fixtures.Module8");
const module9 = Type.alias("Hologram.Test.Fixtures.Module9");

describe("Hologram", () => {
  describe("executeAction()", () => {
    let executeAsyncCommandStub, navigateToPageStub, renderStub;

    beforeEach(() => {
      executeAsyncCommandStub = sinon
        .stub(Hologram, "executeAsyncCommand")
        .callsFake(() => null);

      navigateToPageStub = sinon
        .stub(Hologram, "navigateToPage")
        .callsFake(() => null);

      renderStub = sinon.stub(Hologram, "render").callsFake(() => null);
    });

    afterEach(() => {
      Hologram.executeAsyncCommand.restore();
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

      sinon.assert.notCalled(executeAsyncCommandStub);
      sinon.assert.calledOnce(renderStub);
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

      sinon.assert.notCalled(executeAsyncCommandStub);
      sinon.assert.calledOnce(renderStub);
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

      sinon.assert.notCalled(executeAsyncCommandStub);
      sinon.assert.calledOnce(renderStub);
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

      sinon.assert.calledOnceWithExactly(
        executeAsyncCommandStub,
        Type.commandStruct({
          name: Type.atom("my_command_5"),
          params: Type.map([
            [Type.atom("c"), Type.integer(10)],
            [Type.atom("d"), Type.integer(20)],
          ]),
          target: cid2,
        }),
      );

      sinon.assert.calledOnce(renderStub);
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

      sinon.assert.calledOnceWithExactly(
        executeAsyncCommandStub,
        Type.commandStruct({
          name: Type.atom("my_command_6"),
          params: Type.map([
            [Type.atom("c"), Type.integer(10)],
            [Type.atom("d"), Type.integer(20)],
          ]),
          target: cid1,
        }),
      );

      sinon.assert.calledOnce(renderStub);
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

  it("executeAsyncCommand()", async () => {
    const commandQueueProcessStub = sinon
      .stub(CommandQueue, "process")
      .callsFake(() => null);

    const commandQueuePushStub = sinon
      .stub(CommandQueue, "push")
      .callsFake((_command) => null);

    await Hologram.executeAsyncCommand("dummyCommand");

    sinon.assert.calledOnceWithExactly(commandQueuePushStub, "dummyCommand");
    sinon.assert.calledOnceWithExactly(commandQueueProcessStub);

    CommandQueue.process.restore();
    CommandQueue.push.restore();
  });

  describe("executeLoadPrefetchedPageAction()", () => {
    let eventTargetNode, loadPageStub;

    const html = "my_html";

    const loadPrefetchedPageAction = Type.actionStruct({
      name: Type.atom("__load_prefetched_page__"),
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

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(loadPageStub, pagePath, html);
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

      sinon.assert.notCalled(loadPageStub);
    });
  });

  describe("executePrefetchPageAction()", () => {
    let clientFetchPageStub,
      errorCallbacks,
      eventTargetNode,
      handlePrefetchPageErrorStub,
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
      errorCallbacks = [];

      clientFetchPageStub = sinon
        .stub(Client, "fetchPage")
        .callsFake((_toParam, successCallback, errorCallback) => {
          successCallbacks.push(successCallback);
          errorCallbacks.push(errorCallback);
        });

      handlePrefetchPageSuccessStub = sinon
        .stub(Hologram, "handlePrefetchPageSuccess")
        .callsFake((_mapKey, _resp) => null);

      handlePrefetchPageErrorStub = sinon
        .stub(Hologram, "handlePrefetchPageError")
        .callsFake((_mapKey, _resp) => null);

      eventTargetNode = {id: "dummy_event_target_node"};
    });

    afterEach(() => {
      Client.fetchPage.restore();
      Hologram.handlePrefetchPageSuccess.restore();
      Hologram.handlePrefetchPageError.restore();
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
        errorCallbacks[0],
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageSuccessStub,
        mapKey,
        resp,
      );

      assert.equal(errorCallbacks.length, 1);

      errorCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageErrorStub,
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
        errorCallbacks[0],
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageSuccessStub,
        mapKey,
        resp,
      );

      assert.equal(errorCallbacks.length, 1);

      errorCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageErrorStub,
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
      sinon.assert.notCalled(handlePrefetchPageErrorStub);
    });
  });

  describe("handleUiEvent()", () => {
    let executeActionStub,
      executeAsyncCommandStub,
      executeLoadPrefetchedPageActionStub,
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
      executeAsyncCommandStub = sinon
        .stub(Hologram, "executeAsyncCommand")
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
    });

    afterEach(() => {
      Hologram.executeAction.restore();
      Hologram.executeAsyncCommand.restore();
      Hologram.executeLoadPrefetchedPageAction.restore();
      Hologram.executePrefetchPageAction.restore();
    });

    it("event is ignored", () => {
      const ignoredEvent = {
        ctrlKey: true,
        pageX: 1,
        pageY: 2,
        preventDefault: () => null,
      };

      Hologram.handleUiEvent(
        ignoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeAsyncCommandStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
    });

    it("regular action", () => {
      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(executeAsyncCommandStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
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
              name: Type.atom("__load_prefetched_page__"),
              params: Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
            }),
          ]),
        ],
      ]);

      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeAsyncCommandStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("__load_prefetched_page__"),
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
        executeLoadPrefetchedPageActionStub,
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
              name: Type.atom("__prefetch_page__"),
              params: Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
            }),
          ]),
        ],
      ]);

      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeAsyncCommandStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("__prefetch_page__"),
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

      Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        commandSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);

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

      sinon.assert.calledOnceWithExactly(
        executeAsyncCommandStub,
        expectedCommand,
      );
    });
  });

  describe("loadPage()", () => {
    let historyPushStateStub, windowScrollToStub;

    const pagePath = "/my-page-path";

    const html =
      '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8" /></head><body><div></div></body></html>';

    beforeEach(() => {
      historyPushStateStub = sinon
        .stub(history, "pushState")
        .callsFake((_state, _unused, _url) => null);

      windowScrollToStub = sinon
        .stub(window, "scrollTo")
        .callsFake((_x, _y) => null);

      globalThis.hologram.pageScriptLoaded = true;

      const parser = new DOMParser();

      const doc = parser.parseFromString(
        "<DOCTYPE html><html><head></head><body></body></html>",
        "text/html",
      );

      Hologram.virtualDocument = toVNode(doc.documentElement);
    });

    afterEach(() => {
      history.pushState.restore();
      window.scrollTo.restore();
    });

    it("patches the page", () => {
      Hologram.loadPage(pagePath, html);

      assert.deepStrictEqual(
        vnodeToHtml(Hologram.virtualDocument),
        '<html lang="en"><head><meta charset="utf-8"></head><body><div></div></body></html>',
      );
    });

    it("sets pageScriptLoaded flag to false", () => {
      Hologram.loadPage(pagePath, html);
      assert.isFalse(globalThis.hologram.pageScriptLoaded);
    });

    it("adds an entry to the browser's session history stack", () => {
      Hologram.loadPage(pagePath, html);

      sinon.assert.calledOnceWithExactly(
        historyPushStateStub,
        null,
        null,
        pagePath,
      );
    });

    it("scrolls to the beginning of the page", () => {
      Hologram.loadPage(pagePath, html);
      sinon.assert.calledOnceWithExactly(windowScrollToStub, 0, 0);
    });
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

  describe("handlePrefetchPageError()", () => {
    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      assert.doesNotThrow(() =>
        Hologram.handlePrefetchPageError("dummy_map_key", "my_resp"),
      );
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

      assert.throw(
        () => Hologram.handlePrefetchPageError("dummy_map_key", "my_resp"),
        HologramRuntimeError,
        "page prefetch failed: /my-page-path",
      );
    });
  });

  describe("handlePrefetchPageSuccess()", () => {
    let loadPageStub;

    beforeEach(() => {
      loadPageStub = sinon
        .stub(Hologram, "loadPage")
        .callsFake((_pagePath, _html) => null);
    });

    afterEach(() => Hologram.loadPage.restore());

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.handlePrefetchPageSuccess("dummy_map_key", "my_html");

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

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

      Hologram.handlePrefetchPageSuccess("dummy_map_key", "my_html");

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(
        loadPageStub,
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

      sinon.assert.notCalled(loadPageStub);
    });
  });
});
