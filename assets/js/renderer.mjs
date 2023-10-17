"use strict";

import Interpreter from "./interpreter.mjs";

export default class Renderer {
  // TODO: implement
  static renderPage(pageModule, _params) {
    const layoutModule =
      Interpreter.module(pageModule)["__layout_module__/0"]();
    console.dir(layoutModule);
  }
}
