"use strict";

import Utils from "./utils.mjs";

export default class Type {
  static atom(value) {
    return Utils.freeze({type: "atom", value: value});
  }

  static encodeMapKey(boxed) {
    switch (boxed.type) {
      case "atom":
      case "float":
      case "integer":
        return Type.encodePrimitiveTypeMapKey(boxed);
    }
  }

  static encodePrimitiveTypeMapKey(boxed) {
    return `${boxed.type}(${boxed.value})`;
  }

  static float(value) {
    return Utils.freeze({type: "float", value: value});
  }

  static integer(value) {
    return Utils.freeze({type: "integer", value: value});
  }

  static list(data) {
    return Utils.freeze({type: "list", data: data});
  }

  static string(value) {
    return Utils.freeze({type: "string", value: value});
  }
}
