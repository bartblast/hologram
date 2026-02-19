"use strict";

import Bitstring from "../../bitstring.mjs";
import Interpreter from "../../interpreter.mjs";
import Type from "../../type.mjs";

function box(value) {
  if (value === null || value === undefined) {
    return Type.nil();
  }

  switch (typeof value) {
    case "bigint":
      return Type.integer(value);

    case "boolean":
      return Type.boolean(value);

    case "number":
      return Number.isInteger(value) ? Type.integer(value) : Type.float(value);

    case "string":
      return Type.bitstring(value);
  }

  if (Array.isArray(value)) {
    return Type.list(value.map(box));
  }

  const proto = Object.getPrototypeOf(value);

  if (proto === Object.prototype || proto === null) {
    return Type.map(
      Object.entries(value).map(([k, v]) => [Type.bitstring(k), box(v)]),
    );
  }

  return {type: "native", value: value};
}

const Elixir_Hologram_JS = {
  "exec/1": (code) => {
    return Interpreter.evaluateJavaScriptCode(Bitstring.toText(code));
  },
};

export {box};
export default Elixir_Hologram_JS;
