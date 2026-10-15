"use strict";

import {
  assert,
  assertBoxedError,
  buildFunctionClauseErrorMsg,
  defineRuntimeGlobals,
  setDataLayer,
  sinon,
} from "../support/helpers.mjs";

import Batches from "../../../assets/js/batches.mjs";
import Elixir_Task from "../../../assets/js/elixir/task.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Hologram from "../../../assets/js/hologram.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/task_test.exs
// Always update both together.

describe("Elixir_Task", () => {
  describe("await/1", () => {
    const taskAwait = Elixir_Task["await/1"];
    let taskStruct;

    beforeEach(() => {
      ERTS.promiseRegistry.clear();
      Batches.reset();
      setDataLayer();

      const promise = Promise.resolve(42);
      taskStruct = ERTS.registerPromise(promise);
    });

    afterEach(() => {
      Batches.reset();
      sinon.restore();
      Hologram.dataLayer = null;
    });

    it("returns a Promise (is async)", () => {
      const result = taskAwait(taskStruct);

      assert.instanceOf(result, Promise);
    });

    it("resolves the promise and returns the boxed result", async () => {
      const result = await taskAwait(taskStruct);

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // Awaiting is the one place an action stops running, so the batch it writes to is taken out of
    // the slot here and put back before the caller goes on - client-only, so this one has no
    // consistency twin.
    it("puts the running action's batch back before the caller resumes", async () => {
      const batch = Batches.open("todos");
      const awaited = taskAwait(taskStruct);

      Batches.open("another action");

      await awaited;

      assert.strictEqual(Batches.current(), batch);
    });

    // An app without a data model has no batch to carry - client-only, so this one has no
    // consistency twin either.
    it("awaits the task as it is without a data layer", async () => {
      const carrying = sinon.spy(Batches, "carryAcrossSuspension");
      Hologram.dataLayer = null;

      const result = await taskAwait(taskStruct);

      assert.deepStrictEqual(result, Type.integer(42));
      sinon.assert.notCalled(carrying);
    });

    // The attempted function clauses come from the clause heads the runtime script
    // registers at bundle load, which unit tests don't run, so this twin asserts
    // the message without them.
    it("raises FunctionClauseError if the arg is not a Task struct", () => {
      const expectedMessage = buildFunctionClauseErrorMsg("Task.await/2", [
        Type.integer(123),
        Type.integer(5000),
      ]);

      assertBoxedError(
        () => taskAwait(Type.integer(123)),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("error frame carries the await/2 args", () => {
      const arg = Type.integer(123);

      let caught;

      try {
        taskAwait(arg);
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "Task",
          function: "await",
          arityOrArgs: Type.list([arg, Type.integer(5000)]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });
});
