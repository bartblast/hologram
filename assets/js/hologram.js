"use strict";

import Runtime from "./hologram/runtime"
import Utils from "./hologram/utils"

// Elixir standard library
import Enum from "./hologram/elixir/enum"
import IO from "./hologram/elixir/io"
import Kernel from "./hologram/elixir/kernel"
import Keyword from "./hologram/elixir/keyword"
import Map from "./hologram/elixir/map"
import String from "./hologram/elixir/string"

export default class Hologram {
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
  static run(window, pageModule, serializedState) {
    Hologram.onReady(window.document, () => {
      Runtime.getInstance(window).mountPage(pageModule, serializedState)
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

window.Elixir_Enum = Enum
window.Elixir_IO = IO
window.Elixir_Kernel = Kernel
window.Elixir_Keyword = Keyword
window.Elixir_Map = Map
window.Elixir_String = String

window.Hologram = Hologram