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
  describe("encoder()", () => {
    it("Hologram message", () => {
      const callbackSpy = sinon.spy();

      const msg = {
        event: "dummy_event",
        join_ref: "dummy_join_ref",
        payload: Type.integer(123),
        ref: "dummy_ref",
        topic: "hologram",
      };

      Client.encoder(msg, callbackSpy);

      const expected =
        '["dummy_join_ref","dummy_ref","hologram","dummy_event",[1,"__integer__:123"]]';

      sinon.assert.calledOnceWithExactly(callbackSpy, expected);
    });

    it("Phoenix message", () => {
      const callbackSpy = sinon.spy();

      const msg = {
        event: "dummy_event",
        join_ref: "dummy_join_ref",
        payload: Type.float(1.23),
        ref: "dummy_ref",
        topic: "phoenix",
      };

      Client.encoder(msg, callbackSpy);

      const expected =
        '["dummy_join_ref","dummy_ref","phoenix","dummy_event",{"type":"float","value":1.23}]';

      sinon.assert.calledOnceWithExactly(callbackSpy, expected);
    });
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
