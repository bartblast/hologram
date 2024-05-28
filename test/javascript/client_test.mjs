"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Client", () => {
  it("encoder()", () => {
    const callbackSpy = sinon.spy();

    const msg = {
      event: "dummy_event",
      join_ref: "dummy_join_ref",
      payload: Type.integer(123),
      ref: "dummy_ref",
      topic: "dummy_topic",
    };

    Client.encoder(msg, callbackSpy);

    const expected =
      '["dummy_join_ref","dummy_ref","dummy_topic","dummy_event","__integer__:123"]';

    sinon.assert.calledOnceWithExactly(callbackSpy, expected);
  });

  describe("isConnected()", () => {
    it("socket is null", () => {
      Client.socket = null;
      assert.isFalse(Client.isConnected());
    });

    it("socket is initiated, but not connected", () => {
      Client.socket = {isConnected: () => false};
      assert.isFalse(Client.isConnected());
    });

    it("socket is connected", () => {
      Client.socket = {isConnected: () => true};
      assert.isTrue(Client.isConnected());
    });
  });
});
