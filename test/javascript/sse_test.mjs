"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import Sse from "../../assets/js/sse.mjs";

defineGlobalErlangAndElixirModules();

describe("Sse", () => {
  beforeEach(() => {
    Sse.status = "disconnected";
  });

  afterEach(() => {
    sinon.restore();
  });

  describe("handleError()", () => {
    it("sets status to error", () => {
      sinon.stub(console, "warn");
      Sse.handleError({});

      assert.equal(Sse.status, "error");
    });
  });

  describe("handleOpen()", () => {
    it("sets status to connected", () => {
      sinon.stub(console, "log");
      Sse.handleOpen({});

      assert.equal(Sse.status, "connected");
    });
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
