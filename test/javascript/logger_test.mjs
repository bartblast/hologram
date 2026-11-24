"use strict";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
} from "./support/helpers.mjs";

import Logger from "../../assets/js/logger.mjs";

defineRuntimeGlobals();
registerWebApis();

describe("Logger", () => {
  beforeEach(() => sessionStorage.removeItem(Logger.key));

  afterEach(() => sinon.restore());

  describe("debug()", () => {
    it("Logger key is not set", () => {
      Logger.debug("message_1");

      assert.deepStrictEqual(
        sessionStorage.getItem(Logger.key),
        "[debug] message_1\n",
      );
    });

    it("Logger key is set", () => {
      Logger.debug("message_1");
      Logger.debug("message_2");

      assert.deepStrictEqual(
        sessionStorage.getItem(Logger.key),
        "[debug] message_1\n[debug] message_2\n",
      );
    });

    // The log sits in front of code that has to run, so a line it can't write changes nothing.
    it("does not throw when session storage is full", () => {
      sinon
        .stub(Object.getPrototypeOf(sessionStorage), "setItem")
        .throws(new DOMException("full", "QuotaExceededError"));

      assert.doesNotThrow(() => Logger.debug("message_1"));
    });

    it("does not throw when the log can't be read", () => {
      sinon
        .stub(Object.getPrototypeOf(sessionStorage), "getItem")
        .throws(new DOMException("denied", "SecurityError"));

      assert.doesNotThrow(() => Logger.debug("message_1"));
    });

    it("does not throw when session storage can't be reached", () => {
      sinon.stub(globalThis, "sessionStorage").get(() => {
        throw new DOMException("denied", "SecurityError");
      });

      assert.doesNotThrow(() => Logger.debug("message_1"));
    });
  });

  it("getLogs()", () => {
    Logger.debug("message_1");
    Logger.debug("message_2");

    assert.deepStrictEqual(
      Logger.getLogs(),
      "[debug] message_1\n[debug] message_2\n",
    );
  });
});
