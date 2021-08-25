import "core-js/stable";
import "regenerator-runtime/runtime"; 

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

import Runtime from "./hologram/runtime"
import Utils from "./hologram/utils"

// Elixir standard library
import IO from "./hologram/elixir/io"
import Kernel from "./hologram/elixir/kernel"
import Map from "./hologram/elixir/map"

export default class Hologram {
  // TODO: refactor & test
  static getRuntime(window) {
    if (!window.hologramRuntime) {
      window.hologramRuntime = new Runtime(window)
    }

    return window.hologramRuntime
  }

  // TODO: refactor & test
  static isPatternMatched(left, right) {
    let lType = left.type;
    let rType = right.type;

    if (lType != 'placeholder') {
      if (lType != rType) {
        return false;
      }

      if (lType == 'atom' && left.value != right.value) {
        return false;
      }
    }

    return true;
  }

  // TODO: refactor & test
  static js(js) {
    eval(js.value)
  }

  // TODO: refactor & test
  static onReady(document, callback) {
    if (
      document.readyState === "interactive" ||
      document.readyState === "complete"
    ) {
      callback();
    } else {
      document.addEventListener("DOMContentLoaded", function listener() {
        document.removeEventListener("DOMContentLoaded", listener);
        callback();
      });
    }
  }

  // TODO: refactor & test
  static patternMatchFunctionArgs(params, args) {
    if (args.length != params.length) {
      return false;
    }

    for (let i = 0; i < params.length; ++ i) {
      if (!Hologram.isPatternMatched(params[i], args[i])) {
        return false;
      }
    }

    return true;
  }

  // TODO: refactor & test
  static run(window, pageModule, state) {
    Hologram.onReady(window.document, () => {
      Hologram.getRuntime(window).mountPage(pageModule, state)
    })
  }
}

window.Elixir = class {
  // TODO: refactor & test
  // DEFER: implement other types
  static typeOperator(value, type) {
    if (type == "binary" && value.type == "string") {
      return value
    } else {
      throw "Not supported! (in Elixir.typeOperator)"
    }
  }
}

window.Elixir_IO = IO
window.Elixir_Kernel = Kernel
window.Elixir_Map = Map

window.Hologram = Hologram