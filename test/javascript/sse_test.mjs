"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Sse from "../../assets/js/sse.mjs";

defineGlobalErlangAndElixirModules();

describe("Sse", () => {
  beforeEach(() => {
    Sse.status = "disconnected";
  });

  describe("isConnected()", () => {
    it("returns true when status is connected", () => {
      Sse.status = "connected";

      assert.isTrue(Sse.isConnected());
    });

    it("returns false when status is anything other than connected", () => {
      Sse.status = "disconnected";
      assert.isFalse(Sse.isConnected());

      Sse.status = "connecting";
      assert.isFalse(Sse.isConnected());

      Sse.status = "error";
      assert.isFalse(Sse.isConnected());
    });
  });
});
