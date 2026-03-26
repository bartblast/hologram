"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang from "../erlang/erlang.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_IO = {
  // Deps: [IO.inspect/2]
  "inspect/1": (term) => {
    return Elixir_IO["inspect/2"](term, Type.keywordList());
  },

  // Deps: [IO.inspect/3]
  "inspect/2": (term, opts) => {
    return Elixir_IO["inspect/3"](Type.atom("stdio"), term, opts);
  },

  "inspect/3": function (device, term, opts) {
    if (!Type.isAtom(device) && !Type.isPid(device)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("IO.inspect/3", arguments),
      );
    }

    if (
      Type.isPid(device) ||
      (device.value !== "stdio" && device.value !== "stderr")
    ) {
      const inspectedDevice = Interpreter.inspect(device);

      throw new HologramInterpreterError(
        `device ${inspectedDevice} was attempted to be used on the client side (only :stdio and :stderr devices are available)"`,
      );
    }

    const output = Interpreter.inspect(term, opts);

    console.log(output + "\n");

    return term;
  },

  // Deps: [IO.warn/2]
  "warn/1": (message) => {
    return Elixir_IO["warn/2"](message, Type.list());
  },

  // TODO: provide a more complete implementation.
  // Simplified temporary implementation - just prints the message to the console.
  // The second argument (stacktrace options) is ignored on the client side.
  // Deps: [:erlang.iolist_to_binary/1]
  "warn/2": (message, _stacktraceOrOpts) => {
    const binary = Erlang["iolist_to_binary/1"](message);
    console.warn(Bitstring.toText(binary));

    return Type.atom("ok");
  },

  // TODO: provide a more complete implementation.
  // Simplified temporary implementation - evaluates the message function and delegates to warn/2.
  // Deps: [IO.warn/2]
  "warn_once/3": (_key, messageFun, _stacktraceDropLevels) => {
    return Elixir_IO["warn/2"](
      Interpreter.callAnonymousFunction(messageFun, []),
      Type.list(),
    );
  },
};

export default Elixir_IO;
