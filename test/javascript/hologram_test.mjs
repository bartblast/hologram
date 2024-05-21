"use strict";

import {
  actionFixture,
  assert,
  commandFixture,
  commandQueueItemFixture,
  componentRegistryEntryFixture,
  linkModules,
  sinon,
  unlinkModules,
} from "./support/helpers.mjs";

import CommandQueue from "../../assets/js/command_queue.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Type from "../../assets/js/type.mjs";

import {defineModule1Fixture} from "./support/fixtures/hologram/module_1.mjs";
import {defineModule2Fixture} from "./support/fixtures/hologram/module_2.mjs";
import {defineModule3Fixture} from "./support/fixtures/hologram/module_3.mjs";
import {defineModule4Fixture} from "./support/fixtures/hologram/module_4.mjs";
import {defineModule5Fixture} from "./support/fixtures/hologram/module_5.mjs";
import {defineModule6Fixture} from "./support/fixtures/hologram/module_6.mjs";

const cid1 = Type.bitstring("my_component_1");
const cid2 = Type.bitstring("my_component_2");

const module1 = Type.alias("Module1");
const module2 = Type.alias("Module2");
const module3 = Type.alias("Module3");
const module4 = Type.alias("Module4");
const module5 = Type.alias("Module5");
const module6 = Type.alias("Module6");

describe("Hologram", () => {
  before(() => {
    linkModules();
    defineModule1Fixture();
    defineModule2Fixture();
    defineModule3Fixture();
    defineModule4Fixture();
    defineModule5Fixture();
    defineModule6Fixture();
  });

  after(() => unlinkModules());

  describe("executeAction()", () => {
    let commandQueueProcessStub, renderStub;

    beforeEach(() => {
      CommandQueue.items = [];
      commandQueueProcessStub = sinon
        .stub(CommandQueue, "process")
        .callsFake(() => null);

      renderStub = sinon.stub(Hologram, "render").callsFake(() => null);
    });

    afterEach(() => {
      CommandQueue.process.restore();
      Hologram.render.restore();
    });

    it("without next action or next command", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, componentRegistryEntryFixture({module: module1})],
      ]);

      const action = actionFixture({
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

      const action = actionFixture({
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

      const action = actionFixture({
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

      const action = actionFixture({
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

      const action = actionFixture({
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
  });

  describe("handleEvent()", () => {
    let commandQueueProcessStub, commandQueuePushStub, executeActionStub;

    const actionSpecDom = Type.keywordList([
      [Type.atom("text"), Type.bitstring("my_action")],
    ]);

    const defaultTarget = cid1;
    const eventType = "click";
    const notIgnoredEvent = {pageX: 1, pageY: 2, preventDefault: () => null};

    beforeEach(() => {
      commandQueueProcessStub = sinon
        .stub(CommandQueue, "process")
        .callsFake(() => null);

      commandQueuePushStub = sinon
        .stub(CommandQueue, "push")
        .callsFake(() => null);

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake(() => null);
    });

    afterEach(() => {
      CommandQueue.process.restore();
      CommandQueue.push.restore();
      Hologram.executeAction.restore();
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
    });

    it("action", () => {
      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(commandQueuePushStub);
      sinon.assert.notCalled(commandQueueProcessStub);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("command", () => {
      const commandSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([commandFixture({name: Type.atom("my_command")})]),
        ],
      ]);

      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        commandSpecDom,
        defaultTarget,
      );

      sinon.assert.calledOnce(commandQueuePushStub);
      sinon.assert.calledOnce(commandQueueProcessStub);
      sinon.assert.notCalled(executeActionStub);
    });
  });
});
