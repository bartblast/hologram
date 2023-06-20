"use strict";

export default class Hologram {
  static module(alias) {
    const aliasStr = alias.value;
    let prefixedAliasStr;

    if (aliasStr === "erlang") {
      prefixedAliasStr = "Erlang";
    } else {
      prefixedAliasStr =
        aliasStr.charAt(0).toLowerCase() === aliasStr.charAt(0)
          ? "Erlang_" + aliasStr.charAt(0).toUpperCase() + aliasStr.slice(1)
          : aliasStr;
    }

    const className = prefixedAliasStr.replace(/\./g, "_");

    return Hologram[className];
  }
}
