"use strict";

import {box} from "../js_interop.mjs";

import ERTS from "../erts.mjs";
import Hologram from "../hologram.mjs";
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

    const taskPromise = ERTS.takePromise(taskStruct);

    // Awaiting is where an action stops running and another may run in full before this one comes
    // back, so the batch it is writing to makes the round trip with it (see
    // DataLayer.carryAcrossSuspension). Without a data layer there is no batch to carry.
    const promise =
      Hologram.dataLayer?.carryAcrossSuspension(taskPromise) ?? taskPromise;

    return promise.then(box);
  },
};

export default Elixir_Task;
