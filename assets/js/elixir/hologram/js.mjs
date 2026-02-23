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
    let jsReceiver;

    if (receiver.type === "atom") {
      const receiverName = receiver.value;
      const moduleProxy = Interpreter.moduleProxy(callerModule);

      jsReceiver =
        moduleProxy.__jsBindings__.get(receiverName) ??
        globalThis[receiverName];
    } else if (receiver.type === "native") {
      jsReceiver = receiver.value;
    } else {
      jsReceiver = unbox(receiver);
    }

    const jsMethodName = Bitstring.toText(methodName);
    const jsArgs = args.data.map(unbox);

    return box(jsReceiver[jsMethodName](...jsArgs));
  },

  "exec/1": (code) => {
    return Interpreter.evaluateJavaScriptCode(Bitstring.toText(code));
  },

  "get/3": (callerModule, receiver, property) => {
    let jsReceiver;

    if (receiver.type === "atom") {
      const receiverName = receiver.value;
      const moduleProxy = Interpreter.moduleProxy(callerModule);

      jsReceiver =
        moduleProxy.__jsBindings__.get(receiverName) ??
        globalThis[receiverName];
    } else if (receiver.type === "native") {
      jsReceiver = receiver.value;
    } else {
      jsReceiver = unbox(receiver);
    }

    const jsPropertyName = property.value;

    return box(jsReceiver[jsPropertyName]);
  },

  "new/3": (callerModule, className, args) => {
    let jsClass;

    if (className.type === "atom") {
      const classNameStr = className.value;
      const moduleProxy = Interpreter.moduleProxy(callerModule);

      jsClass =
        moduleProxy.__jsBindings__.get(classNameStr) ??
        globalThis[classNameStr];
    } else if (className.type === "native") {
      jsClass = className.value;
    } else {
      jsClass = unbox(className);
    }

    const jsArgs = args.data.map(unbox);

    return box(new jsClass(...jsArgs));
  },
};

export {box, unbox};
export default Elixir_Hologram_JS;
