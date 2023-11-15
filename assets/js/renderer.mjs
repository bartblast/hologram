"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

// Based on Hologram.Template.Renderer
export default class Renderer {
  // Based on: render_page/2
  static renderPage(pageModule, pageParams, clientsData) {
    const pageModuleRef = Interpreter.module(pageModule);
    const layoutModule = pageModuleRef["__layout_module__/0"]();

    const pageClient = Renderer.#mapFetch(clientsData, Type.bitstring("page"));
    const pageState = Renderer.#mapFetch(pageClient, Type.atom("state"));

    const layoutPropsDOM = Renderer.#buildLayoutPropsDOM(
      pageModule,
      pageClient,
    );

    const vars = Renderer.#aggregateVars(pageParams, pageState);

    const pageDOM = Interpreter.callAnonymousFunction(
      pageModuleRef["template/0"](),
      [vars],
    );

    const layoutNode = Type.tuple([
      Type.atom("component"),
      layoutModule,
      layoutPropsDOM,
      pageDOM,
    ]);

    console.inspect(layoutNode);
  }

  static #aggregateVars(props, state) {
    return Elixir_Hologram_Template_Renderer["aggregate_vars/2"](props, state);
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
