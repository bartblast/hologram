"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_Task from "../../../assets/js/elixir/task.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Elixir_Task", () => {
  describe("await/1", () => {
    const taskAwait = Elixir_Task["await/1"];
    let taskStruct;

    beforeEach(() => {
      ERTS.promiseRegistry.clear();

      const promise = Promise.resolve(42);
      taskStruct = ERTS.registerPromise(promise);
    });

    it("returns a Promise (is async)", () => {
      const result = taskAwait(taskStruct);

      assert.instanceOf(result, Promise);
    });

    it("resolves the promise and returns the boxed result", async () => {
      const result = await taskAwait(taskStruct);

      assert.deepStrictEqual(result, Type.integer(42));
    });
  });
});
