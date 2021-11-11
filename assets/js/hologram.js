"use strict";

import PatternMatcher from "./hologram/pattern_matcher";
import Runtime from "./hologram/runtime";

// Elixir standard library
import Elixir_Ecto_Changeset from "./hologram/elixir/ecto/changeset";
import Elixir_Enum from "./hologram/elixir/enum";
import Elixir_IO from "./hologram/elixir/io";
import Elixir_Kernel from "./hologram/elixir/kernel";
import Elixir_Keyword from "./hologram/elixir/keyword";
import Elixir_Map from "./hologram/elixir/map";
import Elixir_Kernel_SpecialForms from "./hologram/elixir/kernel/special_forms";
import Elixir_String from "./hologram/elixir/string";

export default class Hologram {
  // Covered implicitely in E2E tests.
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
    const window = globalThis.window;

    Hologram.onReady(window.document, () => {
      if (!Runtime.isInitiated) {
        Runtime.init(window);
      }

      Runtime.mountPage(pageClass, serializedState);
    });
  }

  // DELEGATES

  static isFunctionArgsPatternMatched(params, args) {
    return PatternMatcher.isFunctionArgsPatternMatched(params, args);
  }
}

window.Elixir_Ecto_Changeset = Elixir_Ecto_Changeset;
window.Elixir_Enum = Elixir_Enum;
window.Elixir_IO = Elixir_IO;
window.Elixir_Kernel = Elixir_Kernel;
window.Elixir_Kernel_SpecialForms = Elixir_Kernel_SpecialForms;
window.Elixir_Keyword = Elixir_Keyword;
window.Elixir_Map = Elixir_Map;
window.Elixir_String = Elixir_String;

window.Hologram = Hologram;
