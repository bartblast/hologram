"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class Hologram {
  static Interpreter = Interpreter;
  static Type = Type;

  static deserialize(json) {
    return JSON.parse(json, (_key, value) => {
      if (typeof value === "string" && /^__bigint__:-?\d+$/.test(value)) {
        return BigInt(value.substring(11, value.length));
      }
      return value;
    });
  }

  static inspect(term) {
    return Elixir_Kernel.inspect(term, Type.list([]));
  }

  static inspectModuleName(moduleName) {
    if (moduleName.startsWith("Elixir_")) {
      return moduleName.slice(7).replace("_", ".");
    }

    if (moduleName === "Erlang") {
      return ":erlang";
    }

    // starts with "Erlang_"
    return ":" + moduleName.slice(7).toLowerCase();
  }

  static module(alias) {
    const aliasStr = alias.value;
    let prefixedAliasStr;

    if (aliasStr === "erlang") {
      prefixedAliasStr = "Erlang";
    } else {
      prefixedAliasStr =
        aliasStr.charAt(0).toLowerCase() === aliasStr.charAt(0)
          ? "Erlang_" + aliasStr
          : aliasStr;
    }

    const moduleName = prefixedAliasStr.replace(/\./g, "_");
    console.debug(moduleName);

    return globalThis[moduleName];
  }

  static raiseArgumentError(message) {
    return Hologram.raiseError("ArgumentError", message);
  }

  static raiseBadMapError(message) {
    return Hologram.raiseError("BadMapError", message);
  }

  static raiseCompileError(message) {
    return Hologram.raiseError("CompileError", message);
  }

  static raiseError(aliasStr, message) {
    const errorStruct = Type.errorStruct(aliasStr, message);
    return Erlang.error(errorStruct);
  }

  static raiseInterpreterError(message) {
    return Hologram.raiseError("Hologram.InterpreterError", message);
  }

  static raiseKeyError(message) {
    return Hologram.raiseError("KeyError", message);
  }

  static serialize(term) {
    return JSON.stringify(term, (_key, value) =>
      typeof value === "bigint" ? `__bigint__:${value.toString()}` : value
    );
  }
}
