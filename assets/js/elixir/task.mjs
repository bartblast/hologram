"use strict";

import {box} from "./hologram/js.mjs";
import ERTS from "../erts.mjs";

const Elixir_Task = {
  // TODO: this is a minimal port for JS interop only, will be replaced
  // when the full Elixir process model is ported.
  "await/1": async (taskStruct) => {
    return box(await ERTS.takePromise(taskStruct));
  },
};

export default Elixir_Task;
