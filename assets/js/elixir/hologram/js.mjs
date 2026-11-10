"use strict";

import {box} from "../../js_interop.mjs";

import Bitstring from "../../bitstring.mjs";
import ERTS from "../../erts.mjs";
import ElementRefRegistry from "../../element_ref_registry.mjs";
import HologramInterpreterError from "../../errors/interpreter_error.mjs";
import Identifier from "../../identifier.mjs";
import Interpreter from "../../interpreter.mjs";
import Type from "../../type.mjs";

const ELEMENT_EXPECTATION =
  "JS.element/1 takes a ref, like :search or {:message, 42}, or a native value";

// WARNING: must match ELIXIR_REFERENCE_HINT in the client renderer (renderer.mjs).
const ELIXIR_REFERENCE_HINT =
  "an element ref is an identifier, not an Elixir reference";

const MAX_SAFE_BIGINT = BigInt(Number.MAX_SAFE_INTEGER);
const MIN_SAFE_BIGINT = BigInt(Number.MIN_SAFE_INTEGER);

function resolveBinding(term, callerModule) {
  if (term.type === "atom") {
    const name = term.value;
    const moduleProxy = Interpreter.moduleProxy(callerModule);

    if (moduleProxy.__jsBindings__.has(name)) {
      return moduleProxy.__jsBindings__.get(name);
    }

    // A name that is neither an imported binding nor a global cannot resolve, and returning
    // undefined here would surface much later as a TypeError in a minified frame that names
    // neither the module nor the binding.
    if (!(name in globalThis)) {
      throw new HologramInterpreterError(
        `there is no JS binding or global named "${name}" in scope in ${Interpreter.moduleExName(callerModule)} (is a js_import declaration missing?)`,
      );
    }

    return globalThis[name];
  }

  if (Type.isNativeValueStruct(term)) {
    return unboxNativeValue(term);
  }

  return unbox(term, callerModule);
}

function unbox(term, callerModule) {
  switch (term.type) {
    case "anonymous_function":
      return (...jsArgs) => {
        const boxedArgs = jsArgs.slice(0, term.arity).map(box);
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

        if (moduleProxy.__jsBindings__.has(name)) {
          return moduleProxy.__jsBindings__.get(name);
        }
      }

      return term.value in globalThis ? globalThis[term.value] : term.value;

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

    case "map":
      if (Type.isNativeValueStruct(term)) {
        return unboxNativeValue(term);
      }

      {
        const obj = {};

        for (const [_encodedKey, [key, value]] of Object.entries(term.data)) {
          const jsKey =
            key.type === "atom" ? key.value : unbox(key, callerModule);

          Object.defineProperty(obj, jsKey, {
            value: unbox(value, callerModule),
            writable: true,
            enumerable: true,
            configurable: true,
          });
        }

        return obj;
      }

    case "tuple":
      return term.data.map((item) => unbox(item, callerModule));

    default:
      return term;
  }
}

function unboxNativeValue(term) {
  const typeKey = Type.encodeMapKey(Type.atom("type"));
  const jsType = term.data[typeKey][1].value;

  const valueKey = Type.encodeMapKey(Type.atom("value"));
  const boxedValue = term.data[valueKey][1];

  switch (jsType) {
    case "bigint":
      return boxedValue.value;

    case "function":
    case "object":
    case "symbol":
      return ERTS.nativeObjectRegistry.get(boxedValue);

    case "undefined":
      return undefined;
  }
}

const Elixir_Hologram_JS = {
  "call/4": (receiver, methodOrFunction, args, callerModule) => {
    let jsFunction;

    if (Type.isNil(receiver)) {
      jsFunction = resolveBinding(methodOrFunction, callerModule);
    } else {
      const jsReceiver = resolveBinding(receiver, callerModule);
      jsFunction = jsReceiver[methodOrFunction.value].bind(jsReceiver);
    }

    return box(jsFunction(...unbox(args, callerModule)));
  },

  "delete/3": (receiver, property, callerModule) => {
    const jsReceiver = resolveBinding(receiver, callerModule);
    const jsPropertyName = property.value;

    delete jsReceiver[jsPropertyName];

    return receiver;
  },

  "dispatch_event/5": (target, eventType, eventName, opts, callerModule) => {
    const jsTarget = resolveBinding(target, callerModule);
    const EventClass = resolveBinding(eventType, callerModule);
    const jsEventName = Bitstring.toText(eventName);
    const jsOpts = unbox(opts, callerModule);

    return box(jsTarget.dispatchEvent(new EventClass(jsEventName, jsOpts)));
  },

  // A native value is returned as it is, so code that takes a ref or an element alike can pass
  // either here. :window and :document name the window and the document, which no template
  // renders.
  "element/1": (ref) => {
    if (Type.isNativeValueStruct(ref)) {
      return ref;
    }

    if (Type.isAtom(ref) && ref.value === "window") {
      return box(window);
    }

    if (Type.isAtom(ref) && ref.value === "document") {
      return box(document);
    }

    const result = Identifier.check(ref);

    if (result !== null) {
      const hint = Type.isReference(ref) ? ELIXIR_REFERENCE_HINT : result.hint;

      Interpreter.raiseMisuseError(
        Identifier.message(ELEMENT_EXPECTATION, ref, hint),
      );
    }

    const element = ElementRefRegistry.get(ref);

    if (element === null) {
      Interpreter.raiseMisuseError(
        `no element is rendered under the ref ${Interpreter.inspect(ref)}${ElementRefRegistry.missingElementHint(ref)}`,
      );
    }

    return box(element);
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

export {resolveBinding, unbox};
export default Elixir_Hologram_JS;
