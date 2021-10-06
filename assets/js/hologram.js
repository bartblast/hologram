"use strict";

import Runtime from "./hologram/runtime"

// Elixir standard library
import Enum from "./hologram/elixir/enum"
import IO from "./hologram/elixir/io"
import Kernel from "./hologram/elixir/kernel"
import Keyword from "./hologram/elixir/keyword"
import Map from "./hologram/elixir/map"
import SpecialForms from "./hologram/elixir/kernel/special_forms";
import String from "./hologram/elixir/string"

export default class Hologram {
  // Tested implicitely in E2E tests
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

  // Tested implicitely in E2E tests
  static run(window, pageModule, serializedState) {
    Hologram.onReady(window.document, () => {
      Runtime.getInstance(window).mountPage(pageModule, serializedState)
    })
  }
}

window.Elixir_Enum = Enum
window.Elixir_IO = IO
window.Elixir_Kernel = Kernel
window.Elixir_Kernel_SpecialForms = SpecialForms
window.Elixir_Keyword = Keyword
window.Elixir_Map = Map
window.Elixir_String = String

window.Hologram = Hologram