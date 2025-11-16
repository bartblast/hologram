"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const SUPPORTED_INFO_ITEMS = ["module", "name", "arity", "env", "type"];
const INFO_ITEM_SET = new Set(SUPPORTED_INFO_ITEMS);

function raiseArgumentError(argumentIndex, message) {
  Interpreter.raiseArgumentError(
    Interpreter.buildArgumentErrorMsg(argumentIndex, message),
  );
}

function ensureAtom(term, argumentIndex) {
  if (!Type.isAtom(term)) {
    raiseArgumentError(argumentIndex, "not an atom");
  }
}

function ensureInteger(term, argumentIndex) {
  if (!Type.isInteger(term)) {
    raiseArgumentError(argumentIndex, "not an integer");
  }
}

function ensureFunction(term, argumentIndex) {
  if (term.type !== "anonymous_function") {
    raiseArgumentError(argumentIndex, "not a fun");
  }
}

function buildCapturedModuleString(moduleAtom) {
  const moduleValue = moduleAtom.value;

  if (moduleValue.startsWith("Elixir.")) {
    return moduleValue.slice(7);
  }

  return `:${moduleValue}`;
}

function moduleStringToAtom(moduleStr) {
  if (moduleStr.startsWith(":")) {
    return Type.atom(moduleStr.slice(1));
  }

  return Type.alias(moduleStr);
}

function buildCaptureClause(moduleAtom, functionNameAtom, arityValue) {
  return {
    params: () => {
      const patterns = [];

      for (let i = 1; i <= arityValue; i++) {
        patterns.push(Type.variablePattern(`$${i}`));
      }

      return patterns;
    },
    guards: [],
    body: (context) => {
      const args = [];

      for (let i = 1; i <= arityValue; i++) {
        args.push(context.vars[`$${i}`]);
      }

      return Interpreter.callNamedFunction(
        moduleAtom,
        functionNameAtom,
        Type.list(args),
        context,
      );
    },
  };
}

function buildInfoMap(fun) {
  const info = new Map();
  const type = fun.capturedModule ? "external" : "local";

  let moduleValue;

  if (fun.capturedModule) {
    moduleValue = moduleStringToAtom(fun.capturedModule);
  } else if (fun.context?.module) {
    moduleValue = fun.context.module;
  } else {
    moduleValue = Type.atom("erl_eval");
  }

  const nameValue = fun.capturedModule
    ? Type.atom(fun.capturedFunction)
    : Type.atom("anonymous");

  const envValues = fun.context?.vars
    ? Object.values(fun.context.vars)
    : [];

  info.set("module", moduleValue);
  info.set("name", nameValue);
  info.set("arity", Type.integer(fun.arity));
  info.set("env", Type.list(envValues));
  info.set("type", Type.atom(type));

  return info;
}

function infoListFromMap(infoMap) {
  return Type.list(
    SUPPORTED_INFO_ITEMS.map((item) =>
      Type.tuple([Type.atom(item), infoMap.get(item)]),
    ),
  );
}

const Elixir_Function = {
  "capture/3": function (module, functionName, arity) {
    ensureAtom(module, 1);
    ensureAtom(functionName, 2);
    ensureInteger(arity, 3);

    const arityValue = Number(arity.value);

    if (arityValue < 0) {
      raiseArgumentError(3, "out of range");
    }

    if (arityValue > 255) {
      Interpreter.raiseArgumentError("argument error");
    }

    const capturedModuleStr = buildCapturedModuleString(module);
    const clause = buildCaptureClause(module, functionName, arityValue);
    const captureContext = Interpreter.buildContext();

    return Type.functionCapture(
      capturedModuleStr,
      functionName.value,
      arityValue,
      [clause],
      captureContext,
    );
  },

  "info/1": function (fun) {
    ensureFunction(fun, 1);

    const infoMap = buildInfoMap(fun);
    return infoListFromMap(infoMap);
  },

  "info/2": function (fun, item) {
    ensureFunction(fun, 1);

    if (!Type.isAtom(item) || !INFO_ITEM_SET.has(item.value)) {
      raiseArgumentError(2, "invalid item");
    }

    const infoMap = buildInfoMap(fun);
    const value = infoMap.get(item.value);

    return Type.tuple([item, value]);
  },

  "identity/1": (value) => value,
};

export default Elixir_Function;
