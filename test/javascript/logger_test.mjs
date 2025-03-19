"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Logger from "../../assets/js/logger.mjs";

defineGlobalErlangAndElixirModules();

describe("Logger", () => {
  beforeEach(() => sessionStorage.removeItem(Logger.key));

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
