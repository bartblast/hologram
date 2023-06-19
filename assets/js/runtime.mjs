"use strict";

export default class Runtime {
  static getClassByModuleAlias(moduleAlias) {
    const className = Runtime._getClassNameByModuleAlias(moduleAlias);
    return globalThis.__hologram__.classRegistry[className];
  }

  // private
  static _getClassNameByModuleAlias(moduleAlias) {
    const aliasStr = moduleAlias.value;

    if (aliasStr === "erlang") {
      return "Erlang";
    }

    let prefixedAliasStr =
      aliasStr.charAt(0).toLowerCase() === aliasStr.charAt(0)
        ? "Erlang_" + aliasStr.charAt(0).toUpperCase() + aliasStr.slice(1)
        : aliasStr;

    return prefixedAliasStr.replace(/\./g, "_");
  }
}
