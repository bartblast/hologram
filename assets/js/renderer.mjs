"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

const mapFetch = Elixir_Map["fetch!/2"];

// Based on Hologram.Template.Renderer
export default class Renderer {
  static buildLayoutPropsDOM =
    Elixir_Hologram_Template_Renderer["build_layout_props_dom/2"];

  // TODO: implement
  static renderPage(pageModule, _pageParams, clientsData) {
    const _layoutModule =
      Interpreter.module(pageModule)["__layout_module__/0"]();

    const pageClient = mapFetch(clientsData, Type.bitstring("page"));

    const layoutPropsDOM = Renderer.buildLayoutPropsDOM(pageModule, pageClient);
    console.dir(layoutPropsDOM);
  }
}
