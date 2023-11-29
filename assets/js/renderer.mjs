"use strict";

import Bitstring from "./bitstring.mjs";
import Interpreter from "./interpreter.mjs";
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

  // Based on cast_props/2
  static #castProps(propsDom, moduleRef) {
    const propsTuples = Renderer.#filterAllowedProps(propsDom, moduleRef)
      .data.map((propDom) => Renderer.#evalutatePropValue(propDom))
      .map((propDom) => Renderer.#normalizePropName(propDom));

    return Erlang_Maps["from_list/1"](propsTuples);
  }

  static #contextKey(opts) {
    return Interpreter.accessKeywordListElement(
      opts,
      Type.atom("from_context"),
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
      evaluatedValue = Renderer.#valueDomToString(valueDom);
    }

    return Type.tuple([name, evaluatedValue]);
  }

  // Based on filter_allowed_props/2
  static #filterAllowedProps(propsDom, moduleRef) {
    const registeredPropNames = moduleRef["__props__/0"].data
      .filter((prop) => Renderer.#contextKey(prop.data[2]) === null)
      .map((prop) => Elixir_Kernel["to_string/1"](prop.data[0]));

    const allowedPropNames = registeredPropNames.concat(Type.bitstring("cid"));

    return Type.list([
      propsDom.data.filter((propDom) =>
        allowedPropNames.some((name) =>
          Interpreter.isStrictlyEqual(name, propDom.data[0]),
        ),
      ),
    ]);
  }

  // Based on inject_props_from_context/3
  static #injectPropsFromContext(propsFromTemplate, moduleRef, context) {
    const propsFromContextTuples = moduleRef["__props__/0"].data
      .filter((prop) => Renderer.#contextKey(prop.data[2]) !== null)
      .map((prop) => {
        const contextKey = Renderer.#contextKey(prop.data[2]);

        return Type.tuple([
          prop.data[0],
          Erlang_Maps["get/2"](contextKey, context),
        ]);
      });

    const propsFromContext = Erlang_Maps["from_list/1"](propsFromContextTuples);

    return Erlang_Maps["merge/2"](propsFromTemplate, propsFromContext);
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
    const nameStr = Bitstring.toText(name);

    if (valueDom.data.length === 0) {
      return [nameStr, true];
    }

    const valueStr = Renderer.#valueDomToString(valueDom);

    return [nameStr, valueStr];
  }

  // Based on render_attributes/1
  static #renderAttributes(attrsDom) {
    if (attrsDom.data.length === 0) {
      return {};
    }

    return attrsDom.data.reduce((acc, attrDom) => {
      const [nameStr, valueStr] = Renderer.#renderAttribute(
        attrDom.data[0],
        attrDom.data[1],
      );

      acc[nameStr] = valueStr;

      return acc;
    }, {});
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
    return (
      nodes.data
        // There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if}
        .filter((node) => !Type.isNil(node))
        .map((node) => Renderer.renderDom(node, context, slots))
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

  static #valueDomToString(valueDom) {
    return Renderer.#renderNodes(
      valueDom,
      Type.map([]),
      Type.keywordList([]),
    ).join("");
  }
}

// import Erlang_Maps from "./erlang/maps.mjs";
// import HologramInterpreterError from "./errors/interpreter_error.mjs";
// import Interpreter from "./interpreter.mjs";
// import Store from "./store.mjs";

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

//   static #renderDom(dom, context, slots) {
//       switch (nodeType) {
//         case "component":
//           return Renderer.#renderComponentDOM(dom, context, slots);

//         case "element": {
//           const tagName = dom.data[0].value;
//           if (tagName === "slot") {
//             return "(todo: slot)";
//           }
//           return "(todo: element)";
//         }
//       }
//     }
//   }

//   static #buildVars(props, state) {
//     return Erlang_Maps["merge/2"](props, state);
//   }

//   // TODO: finish
//   static #buildLayoutPropsDOM(pageModuleRef, pageClientStruct) {
//     pageModuleRef["__layout_props__/0"]().data.concat(
//       Type.tuple([Type.atom("cid", Type.bitstring("layout"))]),
//     );
//   }

//   static #evaluateTemplate(moduleRef, vars) {
//     return Interpreter.callAnonymousFunction(moduleRef["template/0"](), [vars]);
//   }

//   static #expandSlots(dom, slots) {
//     return Elixir_Hologram_Template_Renderer["expand_slots/2"](dom, slots);
//   }

//   static #hasCidProp(props) {
//     return Elixir_Hologram_Template_Renderer["has_cid_prop?/1"](props);
//   }

//   static #renderComponentDOM(dom, context, slots) {
//     const module = dom.data[1];
//     const propsDOM = dom.data[2];
//     let children = dom.data[3];

//     const expandedChildren = Renderer.#expandSlots(children, slots);

//     const props = Renderer.#injectPropsFromContext(
//       Renderer.#castProps(propsDOM, module),
//       module,
//       context,
//     );

//     if (Type.isTrue(Renderer.#hasCidProp(props))) {
//       return Renderer.#renderStatefulComponent(
//         module,
//         props,
//         expandedChildren,
//         context,
//       );
//     } else {
//       return Renderer.#renderStatelessComponent(
//         module,
//         props,
//         expandedChildren,
//         context,
//       );
//     }
//   }

//   static #renderStatefulComponent(module, props, children, context) {
//     const cid = Erlang_Maps["get/2"](Type.atom("cid"), props);
//     let componentState = Store.getComponentState(cid);
//     let componentContext;

//     const moduleRef = Interpreter.moduleRef(module);

//     if (componentState === null) {
//       if ("init/2" in moduleRef) {
//         const emptyClientStruct =
//           Elixir_Hologram_Component_Client["__struct__/0"]();

//         const clientStruct = moduleRef["init/2"](props, emptyClientStruct);

//         componentState = Erlang_Maps["get/2"](Type.atom("state"), clientStruct);

//         componentContext = Erlang_Maps["get/2"](
//           Type.atom("context"),
//           clientStruct,
//         );
//       } else {
//         const message = `component ${Interpreter.inspect(
//           module,
//         )} is initialized on the client, but doesn't have init/2 implemented`;

//         throw new HologramInterpreterError(message);
//       }
//     } else {
//       componentContext = Store.getComponentContext(cid);
//     }

//     const vars = Renderer.#buildVars(props, componentState);
//     const mergedContext = Erlang_Maps["merge/2"](context, componentContext);

//     const template = Renderer.#renderTemplate(
//       moduleRef,
//       vars,
//       children,
//       mergedContext,
//     );

//     // TODO: remove
//     console.inspect(template);

//     return "(todo: component, in progress)";
//   }

//   // TODO: implement
//   static #renderStatelessComponent() {
//     console.log("#renderStatelessComponent()");
//   }

//   static #renderTemplate(moduleRef, vars, children, context) {
//     const dom = Renderer.#evaluateTemplate(moduleRef, vars);
//     const slots = Type.keywordList([[Type.atom("default"), children]]);

//     return Renderer.#renderDom(dom, context, slots);
//   }
