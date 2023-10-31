"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

// Based on Hologram.Template.Renderer
export default class Renderer {
  // TODO: implement
  static renderPage(pageModule, _pageParams, clientsData) {
    const _layoutModule =
      Interpreter.module(pageModule)["__layout_module__/0"]();

    const pageClient = Renderer.#mapFetch(clientsData, Type.bitstring("page"));

    const layoutPropsDOM = Renderer.#buildLayoutPropsDOM(
      pageModule,
      pageClient,
    );

    console.inspect(layoutPropsDOM);
  }

  static #buildLayoutPropsDOM(pageModule, pageClient) {
    return Elixir_Hologram_Template_Renderer["build_layout_props_dom/2"](
      pageModule,
      pageClient,
    );
  }

  static #mapFetch(map, key) {
    return Elixir_Map["fetch!/2"](map, key);
  }
}
