"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  UUID_REGEX,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";

defineGlobalErlangAndElixirModules();

describe("App", () => {
  describe("instanceId", () => {
    it("is a UUID generated at module load", () => {
      assert.match(App.instanceId, UUID_REGEX);
    });
  });
});
