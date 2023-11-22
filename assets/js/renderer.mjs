"use strict";

import Erlang_Maps from "./erlang/maps.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Store from "./store.mjs";
import Type from "./type.mjs";

// Based on Hologram.Template.Renderer
export default class Renderer {
  // Based on: render_page/2
  static renderPage(pageModule, pageParams) {
    const pageModuleRef = Interpreter.moduleRef(pageModule);
    const layoutModule = pageModuleRef["__layout_module__/0"]();

    const cid = Type.bitstring("page");
    const pageClient = Store.getComponentData(cid);
    const pageState = Store.getComponentState(cid);
    const pageContext = Store.getComponentContext(cid);

    const layoutPropsDOM = Renderer.#buildLayoutPropsDOM(
      pageModule,
      pageClient,
    );

    const vars = Renderer.#aggregateVars(pageParams, pageState);
    const pageDOM = Renderer.#evaluateTemplate(pageModuleRef, vars);

    const layoutNode = Type.tuple([
      Type.atom("component"),
      layoutModule,
      layoutPropsDOM,
      pageDOM,
    ]);

    const html = Renderer.#renderDOM(layoutNode, pageContext, Type.list([]));

    // TODO: remove
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

        case "element": {
          const tagName = dom.data[0].value;
          if (tagName === "slot") {
            return "(todo: slot)";
          }
          return "(todo: element)";
        }

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

  static #evaluateTemplate(moduleRef, vars) {
    return Interpreter.callAnonymousFunction(moduleRef["template/0"](), [vars]);
  }

  static #expandSlots(dom, slots) {
    return Elixir_Hologram_Template_Renderer["expand_slots/2"](dom, slots);
  }

  static #hasCidProp(props) {
    return Elixir_Hologram_Template_Renderer["has_cid_prop?/1"](props);
  }

  static #injectPropsFromContext(propsFromTemplate, module, context) {
    return Elixir_Hologram_Template_Renderer["inject_props_from_context/3"](
      propsFromTemplate,
      module,
      context,
    );
  }

  static #renderComponentDOM(dom, context, slots) {
    const module = dom.data[1];
    const propsDOM = dom.data[2];
    let children = dom.data[3];

    const expandedChildren = Renderer.#expandSlots(children, slots);

    const props = Renderer.#injectPropsFromContext(
      Renderer.#castProps(propsDOM, module),
      module,
      context,
    );

    if (Type.isTrue(Renderer.#hasCidProp(props))) {
      return Renderer.#renderStatefulComponent(
        module,
        props,
        expandedChildren,
        context,
      );
    } else {
      return Renderer.#renderStatelessComponent(
        module,
        props,
        expandedChildren,
        context,
      );
    }
  }

  static #renderStatefulComponent(module, props, children, context) {
    const cid = Erlang_Maps["get/2"](Type.atom("cid"), props);
    let componentState = Store.getComponentState(cid);
    let componentContext;

    const moduleRef = Interpreter.moduleRef(module);

    if (componentState === null) {
      if ("init/2" in moduleRef) {
        const emptyClientStruct =
          Elixir_Hologram_Component_Client["__struct__/0"]();

        const clientStruct = moduleRef["init/2"](props, emptyClientStruct);

        componentState = Erlang_Maps["get/2"](Type.atom("state"), clientStruct);

        componentContext = Erlang_Maps["get/2"](
          Type.atom("context"),
          clientStruct,
        );
      } else {
        const message = `component ${Interpreter.inspect(
          module,
        )} is initialized on the client, but doesn't have init/2 implemented`;

        throw new HologramInterpreterError(message);
      }
    } else {
      componentContext = Store.getComponentContext(cid);
    }

    const vars = Renderer.#aggregateVars(props, componentState);
    const mergedContext = Erlang_Maps["merge/2"](context, componentContext);

    const template = Renderer.#renderTemplate(
      moduleRef,
      vars,
      children,
      mergedContext,
    );

    // TODO: remove
    console.inspect(template);

    return "(todo: component, in progress)";
  }

  // TODO: implement
  static #renderStatelessComponent() {
    console.log("#renderStatelessComponent()");
  }

  static #renderTemplate(moduleRef, vars, children, context) {
    const dom = Renderer.#evaluateTemplate(moduleRef, vars);
    const slots = Type.keywordList([[Type.atom("default"), children]]);

    return Renderer.#renderDOM(dom, context, slots);
  }
}
