"use strict";

import {box} from "./elixir/hologram/js.mjs";
import Type from "./type.mjs";

export default class JsInterop {
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

    return box(value);
  }
}

const $ = JsInterop;
