"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_Task from "../../../assets/js/elixir/task.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/task_test.exs
// Always update both together.

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

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the arg is not a Task struct", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        "Task.await/2",
        [Type.integer(123), Type.integer(5000)],
      );

      assertBoxedError(
        () => taskAwait(Type.integer(123)),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });
});
