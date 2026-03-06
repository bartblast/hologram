"use strict";

import ERTS from "./erts.mjs";
import Type from "./type.mjs";

export default class JsInterop {
  // Converts a JavaScript value to a Hologram boxed type.
  static box(value) {
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
        return Number.isInteger(value)
          ? Type.integer(value)
          : Type.float(value);

      case "string":
        return Type.bitstring(value);
    }

    if (Array.isArray(value)) {
      return Type.list(value.map($.box));
    }

    if (value instanceof Promise) {
      return ERTS.registerPromise(value);
    }

    const proto = Object.getPrototypeOf(value);

    if (proto === Object.prototype || proto === null) {
      return Type.map(
        Object.entries(value).map(([key, value]) => [
          Type.bitstring(key),
          $.box(value),
        ]),
      );
    }

    return {type: "native", value: value};
  }

  // Like box() but uses atom keys for plain objects (matching Elixir action param conventions).
  // Recurses through arrays and nested objects. Delegates to box() for leaf values.
  static boxActionParam(value) {
    if (Array.isArray(value)) {
      return Type.list(value.map((item) => $.boxActionParam(item)));
    }

    if (value !== null && typeof value === "object") {
      const proto = Object.getPrototypeOf(value);

      if (proto === Object.prototype || proto === null) {
        return Type.map(
          Object.entries(value).map(([key, value]) => [
            Type.atom(key),
            $.boxActionParam(value),
          ]),
        );
      }
    }

    return $.box(value);
  }
}

const $ = JsInterop;

const {box, boxActionParam} = JsInterop;
export {box, boxActionParam};
