"use strict";

import Bitstring from "../../bitstring.mjs";
import Interpreter from "../../interpreter.mjs";
import Type from "../../type.mjs";

const MAX_SAFE_BIGINT = BigInt(Number.MAX_SAFE_INTEGER);
const MIN_SAFE_BIGINT = BigInt(Number.MIN_SAFE_INTEGER);

function box(value) {
  if (value === null) {
    return Type.nil();
  }

  switch (typeof value) {
    case "bigint":
    case "undefined":
      return {type: "native", value: value};

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

function resolveBinding(term, callerModule) {
  if (term.type === "atom") {
    const name = term.value;
    const moduleProxy = Interpreter.moduleProxy(callerModule);

    return moduleProxy.__jsBindings__.get(name) ?? globalThis[name];
  }

  if (term.type === "native") {
    return term.value;
  }

  return unbox(term, callerModule);
}

function unbox(term, callerModule) {
  switch (term.type) {
    case "anonymous_function":
      return (...jsArgs) => {
        const boxedArgs = jsArgs.map(box);
        const result = Interpreter.callAnonymousFunction(term, boxedArgs);

        return unbox(result, callerModule);
      };

    case "atom":
      if (term.value === "true") return true;
      if (term.value === "false") return false;
      if (term.value === "nil") return null;

      {
        const name = term.value;
        const moduleProxy = Interpreter.moduleProxy(callerModule);
        const binding = moduleProxy.__jsBindings__.get(name);

        if (binding !== undefined) return binding;
      }

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
      return term.data.map((item) => unbox(item, callerModule));

    case "map": {
      const obj = {};

      for (const [_encodedKey, [key, value]] of Object.entries(term.data)) {
        obj[unbox(key, callerModule)] = unbox(value, callerModule);
      }

      return obj;
    }

    case "native":
      return term.value;

    case "tuple":
      return term.data.map((item) => unbox(item, callerModule));

    default:
      return term;
  }
}

const Elixir_Hologram_JS = {
  "call/4": (receiver, methodName, args, callerModule) => {
    const jsReceiver = resolveBinding(receiver, callerModule);
    const jsMethodName = methodName.value;

    return box(jsReceiver[jsMethodName](...unbox(args, callerModule)));
  },

  "call_async/4": async (receiver, methodName, args, callerModule) => {
    const jsReceiver = resolveBinding(receiver, callerModule);
    const jsMethodName = methodName.value;

    return box(await jsReceiver[jsMethodName](...unbox(args, callerModule)));
  },

  "delete/3": (receiver, property, callerModule) => {
    const jsReceiver = resolveBinding(receiver, callerModule);
    const jsPropertyName = property.value;

    delete jsReceiver[jsPropertyName];

    return receiver;
  },

  "eval/1": (expression) => {
    return box(
      Interpreter.evaluateJavaScriptCode(
        "return (" + Bitstring.toText(expression) + ")",
      ),
    );
  },

  "exec/1": (code) => {
    return box(Interpreter.evaluateJavaScriptCode(Bitstring.toText(code)));
  },

  "get/3": (receiver, property, callerModule) => {
    const jsReceiver = resolveBinding(receiver, callerModule);
    const jsPropertyName = property.value;

    return box(jsReceiver[jsPropertyName]);
  },

  "instanceof/3": (value, className, callerModule) => {
    const jsValue = resolveBinding(value, callerModule);
    const jsClass = resolveBinding(className, callerModule);

    return box(jsValue instanceof jsClass);
  },

  "new/3": (className, args, callerModule) => {
    const jsClass = resolveBinding(className, callerModule);

    return box(new jsClass(...unbox(args, callerModule)));
  },

  "set/4": (receiver, property, value, callerModule) => {
    const jsReceiver = resolveBinding(receiver, callerModule);
    const jsPropertyName = property.value;

    jsReceiver[jsPropertyName] = unbox(value, callerModule);

    return receiver;
  },

  "typeof/2": (value, callerModule) => {
    const jsValue = unbox(value, callerModule);

    return box(typeof jsValue);
  },
};

export {box, resolveBinding, unbox};
export default Elixir_Hologram_JS;
