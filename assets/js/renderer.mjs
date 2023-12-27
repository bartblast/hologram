"use strict";

import Bitstring from "./bitstring.mjs";
import Erlang_Maps from "./erlang/maps.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Store from "./store.mjs";
import Type from "./type.mjs";

import {h as vnode} from "snabbdom";

// Based on Hologram.Template.Renderer
export default class Renderer {
  // Based on render_dom/3
  static renderDom(dom, context, slots) {
    if (Type.isList(dom)) {
      return Renderer.#renderNodes(dom, context, slots);
    }

    const nodeType = dom.data[0].value;

    switch (nodeType) {
      case "component":
        return Renderer.#renderComponent(dom, context, slots);

      case "element":
        return Renderer.#renderElement(dom, context, slots);

      case "expression":
        return Bitstring.toText(
          Elixir_Kernel["to_string/1"](dom.data[1].data[0]),
        );

      case "text":
        return Bitstring.toText(dom.data[1]);
    }
  }

  // Based on build_layout_props_dom/2
  static #buildLayoutPropsDom(pageModuleRef, pageState) {
    const propsFromPage = Erlang_Maps["from_list/1"](
      pageModuleRef["__layout_props__/0"](),
    );

    const propsWithCid = Erlang_Maps["merge/2"](
      propsFromPage,
      Type.map([[Type.atom("cid"), Type.bitstring("layout")]]),
    );

    const propsWithPageState = Erlang_Maps["merge/2"](propsWithCid, pageState);

    return Type.map([
      Object.values(propsWithPageState.data).map(([name, value]) => [
        Type.bitstring(name.value),
        Type.keywordList([[Type.atom("expression"), Type.tuple([value])]]),
      ]),
    ]);
  }

  // Based on cast_props/2
  static #castProps(propsDom, moduleRef) {
    const propsTuples = Renderer.#filterAllowedProps(propsDom, moduleRef)
      .map((propDom) => Renderer.#evalutatePropValue(propDom))
      .map((propDom) => Renderer.#normalizePropName(propDom));

    return Erlang_Maps["from_list/1"](Type.list(propsTuples));
  }

  static #contextKey(opts) {
    return Interpreter.accessKeywordListElement(
      opts,
      Type.atom("from_context"),
    );
  }

  // Based on expand_slots/2 (including fallback case)
  static #expandSlots(dom, slots) {
    if (Type.isList(dom)) {
      return Renderer.#expandSlotsInNodes(dom, slots);
    }

    if (dom.data[0].value === "component") {
      return Renderer.#expandSlotsInComponentNode(dom, slots);
    }

    if (dom.data[0].value === "element") {
      return Renderer.#expandSlotsInElementNode(dom, slots);
    }

    return dom;
  }

  // Based on expand_slots/3 (component case)
  static #expandSlotsInComponentNode(dom, slots) {
    const [nodeType, moduleAlias, propsDom, childrenDom] = dom.data;

    return Type.tuple([
      nodeType,
      moduleAlias,
      propsDom,
      Renderer.#expandSlots(childrenDom, slots),
    ]);
  }

  // Based on expand_slots/3 (element cases)
  static #expandSlotsInElementNode(dom, slots) {
    const [nodeType, tagName, attrsDom, childrenDom] = dom.data;

    if (Interpreter.isStrictlyEqual(tagName, Type.bitstring("slot"))) {
      const slotDom = Interpreter.accessKeywordListElement(
        slots,
        Type.atom("default"),
      );

      return slotDom ? slotDom : Type.nil();
    }

    return Type.tuple([
      nodeType,
      tagName,
      attrsDom,
      Renderer.#expandSlots(childrenDom, slots),
    ]);
  }

  // Based on expand_slots/3 (list case)
  static #expandSlotsInNodes(nodes, slots) {
    return Erlang_Lists["flatten/1"](
      Type.list(nodes.data.map((node) => Renderer.#expandSlots(node, slots))),
    );
  }

  // Based on evaluate_prop_value/2
  static #evalutatePropValue(propDom) {
    const [name, valueDom] = propDom.data;
    let evaluatedValue;

    if (
      valueDom.data.length === 1 &&
      Interpreter.isStrictlyEqual(
        valueDom.data[0].data[0],
        Type.atom("expression"),
      )
    ) {
      evaluatedValue = valueDom.data[0].data[1].data[0];
    } else {
      evaluatedValue = Renderer.#valueDomToBitstring(valueDom);
    }

    return Type.tuple([name, evaluatedValue]);
  }

  static #evaluateTemplate(moduleRef, vars) {
    return Interpreter.callAnonymousFunction(moduleRef["template/0"](), [vars]);
  }

  // Based on filter_allowed_props/2
  static #filterAllowedProps(propsDom, moduleRef) {
    const registeredPropNames = moduleRef["__props__/0"]()
      .data.filter((prop) => Renderer.#contextKey(prop.data[2]) === null)
      .map((prop) => Elixir_Kernel["to_string/1"](prop.data[0]));

    const allowedPropNames = registeredPropNames.concat(Type.bitstring("cid"));

    return propsDom.data.filter((propDom) =>
      allowedPropNames.some((name) =>
        Interpreter.isStrictlyEqual(name, propDom.data[0]),
      ),
    );
  }

  // Based on has_cid_prop?/1
  static #hasCidProp(props) {
    return props.data.hasOwnProperty("atom(cid)");
  }

  static #maybeInitComponent(cid, moduleRef, props) {
    let componentState = Store.getComponentState(cid);
    let componentContext;

    if (componentState === null) {
      if ("init/2" in moduleRef) {
        const emptyClientStruct =
          Elixir_Hologram_Component_Client["__struct__/0"]();

        const clientStruct = moduleRef["init/2"](props, emptyClientStruct);
        Store.putComponentData(cid, clientStruct);

        componentState = Erlang_Maps["get/2"](Type.atom("state"), clientStruct);

        componentContext = Erlang_Maps["get/2"](
          Type.atom("context"),
          clientStruct,
        );
      } else {
        const message = `component ${Interpreter.inspectModuleName(
          moduleRef.__hologramJsModuleName__,
        )} is initialized on the client, but doesn't have init/2 implemented`;

        throw new HologramInterpreterError(message);
      }
    } else {
      componentContext = Store.getComponentContext(cid);
    }

    return [componentState, componentContext];
  }

  // Based on inject_props_from_context/3
  static #injectPropsFromContext(propsFromTemplate, moduleRef, context) {
    const propsFromContextTuples = moduleRef["__props__/0"]()
      .data.filter((prop) => Renderer.#contextKey(prop.data[2]) !== null)
      .map((prop) => {
        const contextKey = Renderer.#contextKey(prop.data[2]);

        return Type.tuple([
          prop.data[0],
          Erlang_Maps["get/2"](contextKey, context),
        ]);
      });

    const propsFromContext = Erlang_Maps["from_list/1"](
      Type.list(propsFromContextTuples),
    );

    return Erlang_Maps["merge/2"](propsFromTemplate, propsFromContext);
  }

  static #mergeNeighbouringTextNodes(nodes) {
    return nodes.reduce((acc, node) => {
      if (
        typeof node === "string" &&
        acc.length > 0 &&
        typeof acc[acc.length - 1] === "string"
      ) {
        acc[acc.length - 1] = acc[acc.length - 1] + node;
      } else {
        acc.push(node);
      }

      return acc;
    }, []);
  }

  // Based on normalize_prop_name/1
  static #normalizePropName(propDom) {
    return Type.tuple([
      Erlang["binary_to_atom/1"](propDom.data[0]),
      propDom.data[1],
    ]);
  }

  // Based on render_attribute/2
  static #renderAttribute(name, valueDom) {
    const nameText = Bitstring.toText(name);

    if (valueDom.data.length === 0) {
      return [nameText, true];
    }

    const valueText = Renderer.#valueDomToText(valueDom);

    return [nameText, valueText];
  }

  // Based on render_attributes/1
  static #renderAttributes(attrsDom) {
    if (attrsDom.data.length === 0) {
      return {};
    }

    return attrsDom.data.reduce((acc, attrDom) => {
      const [nameText, valueText] = Renderer.#renderAttribute(
        attrDom.data[0],
        attrDom.data[1],
      );

      acc[nameText] = valueText;

      return acc;
    }, {});
  }

  // Based on render_dom/3 (component case)
  static #renderComponent(dom, context, slots) {
    const moduleRef = Interpreter.moduleRef(dom.data[1]);
    const propsDom = dom.data[2];
    let childrenDom = dom.data[3];

    const expandedChildrenDom = Renderer.#expandSlots(childrenDom, slots);

    const props = Renderer.#injectPropsFromContext(
      Renderer.#castProps(propsDom, moduleRef),
      moduleRef,
      context,
    );

    if (Renderer.#hasCidProp(props)) {
      return Renderer.#renderStatefulComponent(
        moduleRef,
        props,
        expandedChildrenDom,
        context,
      );
    } else {
      return Renderer.#renderTemplate(
        moduleRef,
        props,
        expandedChildrenDom,
        context,
      );
    }
  }

  // Based on render_dom/3 (element & slot case)
  static #renderElement(dom, context, slots) {
    const tagName = Bitstring.toText(dom.data[1]);

    if (tagName === "slot") {
      return Renderer.#renderSlotElement(slots, context);
    }

    const attrsDom = dom.data[2];
    const childrenDom = dom.data[3];

    const attrsVdom = Renderer.#renderAttributes(attrsDom);
    const childrenVdom = Renderer.renderDom(childrenDom, context, slots);

    return vnode(tagName, {attrs: attrsVdom}, childrenVdom);
  }

  // Based on render_dom/3 (list case)
  static #renderNodes(nodes, context, slots) {
    return Renderer.#mergeNeighbouringTextNodes(
      nodes.data
        // There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if}
        .filter((node) => !Type.isNil(node))
        .map((node) => Renderer.renderDom(node, context, slots))
        .flat(),
    );
  }

  // Based on render_dom/3 (slot case)
  static #renderSlotElement(slots, context) {
    const slotDom = Interpreter.accessKeywordListElement(
      slots,
      Type.atom("default"),
    );
    return Renderer.renderDom(slotDom, context, Type.keywordList([]));
  }

  // Based on render_stateful_component/4
  static #renderStatefulComponent(moduleRef, props, childrenDom, context) {
    const cid = Erlang_Maps["get/2"](Type.atom("cid"), props);

    const [componentState, componentContext] = Renderer.#maybeInitComponent(
      cid,
      moduleRef,
      props,
    );

    const vars = Erlang_Maps["merge/2"](props, componentState);
    const mergedContext = Erlang_Maps["merge/2"](context, componentContext);

    return Renderer.#renderTemplate(
      moduleRef,
      vars,
      childrenDom,
      mergedContext,
    );
  }

  // Based on render_template/4
  static #renderTemplate(moduleRef, vars, childrenDom, context) {
    const dom = Renderer.#evaluateTemplate(moduleRef, vars);
    const slots = Type.keywordList([[Type.atom("default"), childrenDom]]);

    return Renderer.renderDom(dom, context, slots);
  }

  static #valueDomToBitstring(valueDom) {
    const bitstringChunks = valueDom.data.map((node) => {
      const nodeType = node.data[0].value;

      if (nodeType === "text") {
        return node.data[1];
      } else {
        return Elixir_Kernel["to_string/1"](node.data[1].data[0]);
      }
    });

    return Bitstring.merge(bitstringChunks);
  }

  static #valueDomToText(valueDom) {
    return Bitstring.toText(Renderer.#valueDomToBitstring(valueDom));
  }
}

// import Erlang_Maps from "./erlang/maps.mjs";

//   // Based on: render_page/2
//   static renderPage(pageModule, pageParams) {
//     const pageModuleRef = Interpreter.moduleRef(pageModule);
//     const layoutModule = pageModuleRef["__layout_module__/0"]();

//     const cid = Type.bitstring("page");
//     const pageClientStruct = Store.getComponentData(cid);
//     const pageState = Store.getComponentState(cid);
//     const pageContext = Store.getComponentContext(cid);

//     const layoutPropsDOM = Renderer.#buildLayoutPropsDOM(
//       pageModuleRef,
//       pageClientStruct,
//     );

//     const vars = Renderer.#buildVars(pageParams, pageState);
//     const pageDOM = Renderer.#evaluateTemplate(pageModuleRef, vars);

//     const layoutNode = Type.tuple([
//       Type.atom("component"),
//       layoutModule,
//       layoutPropsDOM,
//       pageDOM,
//     ]);

//     const html = Renderer.#renderDom(layoutNode, pageContext, Type.list([]));

//     // TODO: remove
//     console.inspect(html);
//   }
