"use strict";

import {box} from "../js_interop.mjs";

import ERTS from "../erts.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_Task = {
  // TODO: this is a minimal port for JS interop only, will be replaced
  // when the full Elixir process model is ported.
  "await/1": (taskStruct) => {
    if (!Type.isStruct(taskStruct, "Task")) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("Task.await/2", [
          taskStruct,
          Type.integer(5000),
        ]),
      );
    }

    return ERTS.takePromise(taskStruct).then(box);
  },
};

export default Elixir_Task;
