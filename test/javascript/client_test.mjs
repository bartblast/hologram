"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";

describe("Client", () => {
  before(() => linkModules());
  after(() => unlinkModules());

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
