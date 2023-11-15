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
    const pageContext = Renderer.#mapFetch(pageClient, Type.atom("context"));

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

    const html = Renderer.#renderDOM(layoutNode, pageContext, Type.list([]));

    console.inspect(html);
  }

  // Based on: render_dom/3
  static #renderDOM(dom, context, slots) {
    if (Type.isList(dom)) {
      return "(todo: node list)";
    } else {
      const nodeType = dom.data[0].value;

      switch (nodeType) {
        case "component":
          return Renderer.#renderComponentDOM(dom, context, slots);

        case "element":
          const tagName = dom.data[0].value;
          if (tagName === "slot") {
            return "(todo: slot)";
          }
          return "(todo: element)";

        case "expression":
          return "(todo: expression)";

        case "text":
          return "(todo: text)";
      }
    }
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

  static #castProps(propsDOM, module) {
    return Elixir_Hologram_Template_Renderer["cast_props/2"](propsDOM, module);
  }

  static #expandSlots(dom, slots) {
    return Elixir_Hologram_Template_Renderer["expand_slots/2"](dom, slots);
  }

  static #injectContextProps(propsFromTemplate, module, context) {
    return Elixir_Hologram_Template_Renderer["inject_context_props/3"](
      propsFromTemplate,
      module,
      context,
    );
  }

  static #mapFetch(map, key) {
    return Elixir_Map["fetch!/2"](map, key);
  }

  static #renderComponentDOM(dom, context, slots) {
    const module = dom.data[1];
    const propsDOM = dom.data[2];
    let children = dom.data[3];

    children = Renderer.#expandSlots(children, slots);

    const props = Renderer.#injectContextProps(
      Renderer.#castProps(propsDOM, module),
      module,
      context,
    );

    console.inspect(props);

    return "(todo: component)";
  }
}
