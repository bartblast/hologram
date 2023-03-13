"use strict";

import Runtime from "../../runtime";
import Type from "../../type";

export default class Router {
  // DEFER: test
  static static_path(filePath) {
    const pathWithDigest = Runtime.staticDigestStore[filePath.value]
    return pathWithDigest ? Type.string(pathWithDigest) : filePath
  }
}