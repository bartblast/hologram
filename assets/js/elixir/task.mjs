"use strict";

import {box} from "../js_interop.mjs";

import Batches from "../batches.mjs";
import ERTS from "../erts.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_Task = {
  // TODO: this is a minimal port for JS interop only, will be replaced
  // when the full Elixir process model is ported.
  "await/1": (taskStruct) => {
    if (!Type.isStruct(taskStruct, "Task")) {
      Interpreter.raiseFunctionClauseError("Task", "await", 2, [
        taskStruct,
        Type.integer(5000),
      ]);
    }

    // Awaiting is where an action stops running and another may run in full before this one comes
    // back, so the batch it is writing to has to make the round trip with it - otherwise it would
    // resume into whichever action started meanwhile, and write, close or discard that one's batch.
    const promise = Batches.carryAcrossSuspension(ERTS.takePromise(taskStruct));

    return promise.then(box);
  },
};

export default Elixir_Task;
