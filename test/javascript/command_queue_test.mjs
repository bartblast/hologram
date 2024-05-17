"use strict";

import {assert, linkModules, sinon, unlinkModules} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import CommandQueue from "../../assets/js/command_queue.mjs";

describe("CommandQueue", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("getNextPending()", () => {
    it("empty queue", () => {
      CommandQueue.items = {};
      assert.isNull(CommandQueue.getNextPending());
    });

    it("non-empty queue", () => {
      const itemA = {
        id: "a",
        command: "dummy_command_a",
        status: "sending",
      };

      const itemC = {
        id: "c",
        command: "dummy_command_c",
        status: "pending",
      };

      const itemB = {
        id: "b",
        command: "dummy_command_b",
        status: "pending",
      };

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
        a: {
          id: "a",
          command: "dummy_command_a",
          status: "failed",
        },
        b: {
          id: "b",
          command: "dummy_command_b",
          status: "pending",
        },
        c: {
          id: "c",
          command: "dummy_command_c",
          status: "failed",
        },
        d: {
          id: "d",
          command: "dummy_command_d",
          status: "pending",
        },
      };
    });

    it("queue is already being processed", () => {
      CommandQueue.isProcessing = true;

      CommandQueue.process();

      assert.equal(CommandQueue.items.b.status, "pending");
      assert.equal(CommandQueue.items.d.status, "pending");
    });

    it("client is not connected", () => {
      CommandQueue.isProcessing = false;

      const isConnectedStub = sinon
        .stub(Client, "isConnected")
        .callsFake(() => false);

      CommandQueue.process();

      assert.equal(CommandQueue.items.b.status, "pending");
      assert.equal(CommandQueue.items.d.status, "pending");

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

      sinon.assert.calledOnce(isConnectedStub);
      Client.isConnected.restore();
    });

    it("non-empty queue, queue is not being processed and the client is connected", () => {
      CommandQueue.isProcessing = false;

      const isConnectedStub = sinon
        .stub(Client, "isConnected")
        .callsFake(() => true);

      const successCallbacks = [];
      const pushStub = sinon
        .stub(Client, "push")
        .callsFake((_event, _payload, successCallback, _failureCallback) =>
          successCallbacks.push(successCallback),
        );

      CommandQueue.process();

      assert.equal(Object.keys(CommandQueue.items).length, 4);
      assert.equal(CommandQueue.items.a.status, "failed");
      assert.equal(CommandQueue.items.b.status, "sending");
      assert.equal(CommandQueue.items.c.status, "failed");
      assert.equal(CommandQueue.items.d.status, "sending");

      successCallbacks.forEach((callback) => callback());

      assert.deepStrictEqual(CommandQueue.items, {
        a: {
          id: "a",
          command: "dummy_command_a",
          status: "failed",
        },
        c: {
          id: "c",
          command: "dummy_command_c",
          status: "failed",
        },
      });

      sinon.assert.calledOnce(isConnectedStub);
      Client.isConnected.restore();

      sinon.assert.calledTwice(pushStub);
      Client.push.restore();
    });
  });

  it("push()", () => {
    CommandQueue.items = {};

    CommandQueue.push("dummy_command");

    const id = Object.keys(CommandQueue.items)[0];
    assert.match(
      id,
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );

    const expectedItems = {};
    expectedItems[id] = {
      id: id,
      command: "dummy_command",
      status: "pending",
    };

    assert.deepStrictEqual(CommandQueue.items, expectedItems);
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
});
