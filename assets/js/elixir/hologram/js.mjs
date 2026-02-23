"use strict";

import Bitstring from "../../bitstring.mjs";
import Interpreter from "../../interpreter.mjs";
import Type from "../../type.mjs";

const MAX_SAFE_BIGINT = BigInt(Number.MAX_SAFE_INTEGER);
const MIN_SAFE_BIGINT = BigInt(Number.MIN_SAFE_INTEGER);

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

function resolveReceiver(callerModule, receiver) {
  if (receiver.type === "atom") {
    const receiverName = receiver.value;
    const moduleProxy = Interpreter.moduleProxy(callerModule);

    return (
      moduleProxy.__jsBindings__.get(receiverName) ?? globalThis[receiverName]
    );
  }

  if (receiver.type === "native") {
    return receiver.value;
  }

  return unbox(receiver);
}

function unbox(term) {
  switch (term.type) {
    case "atom":
      if (term.value === "true") return true;
      if (term.value === "false") return false;
      if (term.value === "nil") return null;
      return term.value;

    case "bitstring":
      return Bitstring.toText(term);

    case "float":
      return term.value;

    case "integer":
      if (term.value >= MIN_SAFE_BIGINT && term.value <= MAX_SAFE_BIGINT) {
        return Number(term.value);
      }

      return term.value;

    case "list":
      return term.data.map(unbox);

    case "map": {
      const obj = {};

      for (const [_encodedKey, [key, value]] of Object.entries(term.data)) {
        obj[unbox(key)] = unbox(value);
      }

      return obj;
    }

    case "native":
      return term.value;

    case "tuple":
      return term.data.map(unbox);

    default:
      return term;
  }
}

const Elixir_Hologram_JS = {
  "call/4": (callerModule, receiver, methodName, args) => {
    const jsReceiver = resolveReceiver(callerModule, receiver);
    const jsMethodName = Bitstring.toText(methodName);
    const jsArgs = args.data.map(unbox);

    return box(jsReceiver[jsMethodName](...jsArgs));
  },

  "exec/1": (code) => {
    return Interpreter.evaluateJavaScriptCode(Bitstring.toText(code));
  },

  "get/3": (callerModule, receiver, property) => {
    const jsReceiver = resolveReceiver(callerModule, receiver);
    const jsPropertyName = property.value;

    return box(jsReceiver[jsPropertyName]);
  },

  "new/3": (callerModule, className, args) => {
    const jsClass = resolveReceiver(callerModule, className);
    const jsArgs = args.data.map(unbox);

    return box(new jsClass(...jsArgs));
  },

  "set/4": (callerModule, receiver, property, value) => {
    const jsReceiver = resolveReceiver(callerModule, receiver);
    const jsPropertyName = property.value;

    jsReceiver[jsPropertyName] = unbox(value);

    return receiver;
  },
};

export {box, resolveReceiver, unbox};
export default Elixir_Hologram_JS;
