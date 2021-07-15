import "core-js/stable";
import "regenerator-runtime/runtime"; 

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

import Runtime from "./hologram/runtime"

export default class Hologram {
  // TODO: refactor & test functions below

  static evaluate(value) {
    switch (value.type) {
      case "integer":
        return `${value.value}`
    }
  }

  static get_module(name) {
    return eval(name.replace(/\./g, ""))
  }

  static getRuntime() {
    if (!window.hologramRuntime) {
      window.hologramRuntime = new Runtime()
    }

    return window.hologramRuntime
  }

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

  static js(js) {
    eval(js.value)
  }

  static objectKey(key) {
    switch (key.type) {
      case 'atom':
        return `~atom[${key.value}]`

      case 'string':
        return `~string[${key.value}]`
        
      default:
        throw 'Not implemented, at HologramPage.objectKey()'
    }
  }

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

  static run(window, pageModule, state) {
    Hologram.onReady(window.document, () => {
      Hologram.getRuntime().restart(pageModule, state)
    })
  }
}

class Kernel {
  static $add(left, right) {
    let type = left.type == "integer" && right.type == "integer" ? "integer" : "float"
    return { type: type, value: left.value + right.value }
  }

  static $dot(left, right) {
    return cloneDeep(left.data[Hologram.objectKey(right)])
  }
}

class Map {
  static put(map, key, value) {
    let mapClone = cloneDeep(map)
    mapClone.data[Hologram.objectKey(key)] = value
    return mapClone;
  }
}

window.Hologram = Hologram
window.Kernel = Kernel
window.Map = Map