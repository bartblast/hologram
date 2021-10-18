"use strict";

import PatternMatcher from "./hologram/pattern_matcher";
import Runtime from "./hologram/runtime";

// Elixir standard library
import Enum from "./hologram/elixir/enum";
import IO from "./hologram/elixir/io";
import Kernel from "./hologram/elixir/kernel";
import Keyword from "./hologram/elixir/keyword";
import Map from "./hologram/elixir/map";
import SpecialForms from "./hologram/elixir/kernel/special_forms";
import String from "./hologram/elixir/string";

export default class Hologram {
  // Tested implicitely in E2E tests.
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

  // Covered implicitely in E2E tests.
  static run(pageClass, serializedState) {
    const window = globalThis.window

    Hologram.onReady(window.document, () => {
      if (!Runtime.isInitiated) {
        Runtime.init(window)
      }

      Runtime.mountPage(pageClass, serializedState);
    });
  }

  // DELEGATES

  static isFunctionArgsPatternMatched(params, args) {
    return PatternMatcher.isFunctionArgsPatternMatched(params, args);
  }
}

window.Elixir_Enum = Enum;
window.Elixir_IO = IO;
window.Elixir_Kernel = Kernel;
window.Elixir_Kernel_SpecialForms = SpecialForms;
window.Elixir_Keyword = Keyword;
window.Elixir_Map = Map;
window.Elixir_String = String;

window.Hologram = Hologram;
