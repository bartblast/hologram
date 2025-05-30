"use strict";

import {
  assert,
  commandQueueItemFixture,
  componentRegistryEntryFixture,
  defineGlobalErlangAndElixirModules,
  sinon,
  UUID_REGEX,
} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import CommandQueue from "../../assets/js/command_queue.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("CommandQueue", () => {
  describe("fail()", () => {
    beforeEach(() => {
      CommandQueue.items = {
        a: commandQueueItemFixture({id: "a", command: "dummy_command_a"}),
        b: commandQueueItemFixture({
          id: "b",
          command: "dummy_command_b",
          status: "failed",
          failCount: 2,
        }),
      };
    });

    it("not failed yet", () => {
      CommandQueue.fail("a");

      assert.deepStrictEqual(CommandQueue.items, {
        a: commandQueueItemFixture({
          id: "a",
          command: "dummy_command_a",
          status: "failed",
          failCount: 1,
        }),
        b: commandQueueItemFixture({
          id: "b",
          command: "dummy_command_b",
          status: "failed",
          failCount: 2,
        }),
      });
    });

    it("already failed", () => {
      CommandQueue.fail("b");

      assert.deepStrictEqual(CommandQueue.items, {
        a: commandQueueItemFixture({id: "a", command: "dummy_command_a"}),
        b: commandQueueItemFixture({
          id: "b",
          command: "dummy_command_b",
          status: "failed",
          failCount: 3,
        }),
      });
    });
  });

  describe("getNextPending()", () => {
    it("empty queue", () => {
      CommandQueue.items = {};
      assert.isNull(CommandQueue.getNextPending());
    });

    it("non-empty queue", () => {
      const itemA = commandQueueItemFixture({
        id: "a",
        command: "dummy_command_a",
        status: "sending",
      });

      const itemC = commandQueueItemFixture({
        id: "c",
        command: "dummy_command_c",
      });

      const itemB = commandQueueItemFixture({
        id: "b",
        command: "dummy_command_b",
      });

      CommandQueue.items = {};
      CommandQueue.items["a"] = itemA;
      CommandQueue.items["c"] = itemC;
      CommandQueue.items["b"] = itemB;

      assert.equal(CommandQueue.getNextPending(), itemC);
    });
  });

  describe("process()", () => {
    beforeEach(() => {
      CommandQueue.items = {
        a: commandQueueItemFixture({
          id: "a",
          command: "dummy_command_a",
          status: "failed",
          failCount: 2,
        }),
        b: commandQueueItemFixture({id: "b", command: "dummy_command_b"}),
        c: commandQueueItemFixture({
          id: "c",
          command: "dummy_command_c",
          status: "failed",
          failCount: 2,
        }),
        d: commandQueueItemFixture({id: "d", command: "dummy_command_d"}),
      };
    });

    it("queue is already being processed", () => {
      CommandQueue.isProcessing = true;

      CommandQueue.process();

      assert.equal(CommandQueue.items.b.status, "pending");
      assert.equal(CommandQueue.items.d.status, "pending");

      assert.isTrue(CommandQueue.isProcessing);
    });

    it("client is not connected", () => {
      CommandQueue.isProcessing = false;

      const isConnectedStub = sinon
        .stub(Client, "isConnected")
        .callsFake(() => false);

      CommandQueue.process();

      assert.equal(CommandQueue.items.b.status, "pending");
      assert.equal(CommandQueue.items.d.status, "pending");

      assert.isFalse(CommandQueue.isProcessing);

      sinon.assert.calledOnce(isConnectedStub);
      Client.isConnected.restore();
    });

    it("empty queue, queue is not being processed and the client is connected", () => {
      CommandQueue.items = {};
      CommandQueue.isProcessing = false;

      const isConnectedStub = sinon
        .stub(Client, "isConnected")
        .callsFake(() => true);

      CommandQueue.process();

      assert.deepStrictEqual(CommandQueue.items, {});

      assert.isFalse(CommandQueue.isProcessing);

      sinon.assert.calledOnce(isConnectedStub);
      Client.isConnected.restore();
    });

    it("non-empty queue, queue is not being processed and the client is connected, next action is nil", () => {
      CommandQueue.isProcessing = false;

      const isConnectedStub = sinon
        .stub(Client, "isConnected")
        .callsFake(() => true);

      const successCallbacks = [];

      const sendCommandStub = sinon
        .stub(Client, "sendCommand")
        .callsFake((_payload, successCallback, _failureCallback) =>
          successCallbacks.push(successCallback),
        );

      const executeAction = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);

      CommandQueue.process();

      assert.equal(CommandQueue.size(), 4);
      assert.equal(CommandQueue.items.a.status, "failed");
      assert.equal(CommandQueue.items.b.status, "sending");
      assert.equal(CommandQueue.items.c.status, "failed");
      assert.equal(CommandQueue.items.d.status, "sending");

      assert.isFalse(CommandQueue.isProcessing);

      successCallbacks.forEach((callback) => callback("Type.nil()"));

      assert.deepStrictEqual(CommandQueue.items, {
        a: commandQueueItemFixture({
          id: "a",
          command: "dummy_command_a",
          status: "failed",
          failCount: 2,
        }),
        c: commandQueueItemFixture({
          id: "c",
          command: "dummy_command_c",
          status: "failed",
          failCount: 2,
        }),
      });

      sinon.assert.calledOnce(isConnectedStub);
      Client.isConnected.restore();

      sinon.assert.calledTwice(sendCommandStub);
      Client.sendCommand.restore();

      sinon.assert.notCalled(executeAction);
      Hologram.executeAction.restore();
    });

    it("it executes next action if it is not nil", () => {
      CommandQueue.isProcessing = false;

      sinon.stub(Client, "isConnected").callsFake(() => true);

      const successCallbacks = [];

      sinon
        .stub(Client, "sendCommand")
        .callsFake((_payload, successCallback, _failureCallback) =>
          successCallbacks.push(successCallback),
        );

      const executeAction = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);

      CommandQueue.process();

      successCallbacks.forEach((callback) => callback('"dummy_action"'));

      Client.isConnected.restore();
      Client.sendCommand.restore();

      sinon.assert.calledTwice(executeAction);
      sinon.assert.alwaysCalledWithExactly(executeAction, "dummy_action");
      Hologram.executeAction.restore();
    });

    it("commands fail", () => {
      CommandQueue.isProcessing = false;

      sinon.stub(Client, "isConnected").callsFake(() => true);

      const failureCallbacks = [];

      sinon
        .stub(Client, "sendCommand")
        .callsFake((_payload, _successCallback, failureCallback) =>
          failureCallbacks.push(failureCallback),
        );

      CommandQueue.process();

      failureCallbacks.forEach((callback) => {
        assert.throw(
          () => callback("my_response"),
          HologramRuntimeError,
          "command failed: my_response",
        );
      });

      assert.deepStrictEqual(CommandQueue.items, {
        a: commandQueueItemFixture({
          id: "a",
          command: "dummy_command_a",
          status: "failed",
          failCount: 2,
        }),
        b: commandQueueItemFixture({
          id: "b",
          command: "dummy_command_b",
          status: "failed",
          failCount: 1,
        }),
        c: commandQueueItemFixture({
          id: "c",
          command: "dummy_command_c",
          status: "failed",
          failCount: 2,
        }),
        d: commandQueueItemFixture({
          id: "d",
          command: "dummy_command_d",
          status: "failed",
          failCount: 1,
        }),
      });

      Client.isConnected.restore();
      Client.sendCommand.restore();
    });
  });

  describe("push()", () => {
    const name = Type.bitstring("my_command");

    const params = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const target = Type.bitstring("my_component");

    beforeEach(() => {
      CommandQueue.items = {};
    });

    it("valid target", () => {
      const module = Type.alias("MyModule");

      ComponentRegistry.entries = Type.map([
        [target, componentRegistryEntryFixture({module: module})],
      ]);

      const command = Type.commandStruct({name, params, target});

      CommandQueue.push(command);

      const id = Object.keys(CommandQueue.items)[0];

      assert.match(id, UUID_REGEX);

      const expectedItems = {};

      expectedItems[id] = commandQueueItemFixture({
        id: id,
        failCount: 0,
        module: module,
        name: name,
        params: params,
        status: "pending",
        target: target,
      });

      assert.deepStrictEqual(CommandQueue.items, expectedItems);
    });

    it("invalid target", () => {
      ComponentRegistry.clear();

      const command = Type.commandStruct({
        name,
        params,
        target: Type.atom("my_target"),
      });

      assert.throw(
        () => CommandQueue.push(command),
        HologramRuntimeError,
        "invalid command target, there is no component with CID: :my_target",
      );
    });
  });

  it("remove()", () => {
    CommandQueue.items = {
      id1: "dummy_item_1",
      id2: "dummy_item_2",
      id3: "dummy_item_3",
    };

    CommandQueue.remove("id2");

    assert.deepStrictEqual(CommandQueue.items, {
      id1: "dummy_item_1",
      id3: "dummy_item_3",
    });
  });

  it("size()", () => {
    CommandQueue.items = {
      id1: "dummy_item_1",
      id2: "dummy_item_2",
      id3: "dummy_item_3",
    };

    assert.equal(CommandQueue.size(), 3);
  });
});
