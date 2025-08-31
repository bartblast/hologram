// Based on Elixir Hologram.Template.Renderer

"use strict";

import Bitstring from "./bitstring.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Hologram from "./hologram.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

import {h as vnode} from "snabbdom";
import vnodeToHtml from "snabbdom-to-html";

export default class Renderer {
  // Based on: https://github.com/SukkaW/fast-escape-html (941dab1ec4b1ad7ba5f1899adcd121563ab10dab)
  static escapeHtml(text) {
    const regexEscapedChars = /["&'<>]/;
    const match = regexEscapedChars.exec(text);

    // Faster than !match since there is no type conversion
    if (match === null) {
      return text;
    }

    let entity = "";
    let escaped = "";

    let index = match.index;
    let lastIndex = 0;

    const len = text.length;

    // Switch cases ordered by frequency of occurrence in typical HTML content:
    // Based on analysis of the ECMAScript specification (https://tc39.es/ecma262):
    //  <  Most common, used in tags and comparisons
    //  >  Often paired with <, but slightly less frequent
    //  "  Preferred over ' in HTML attributes
    //  '  Less common, mainly in attribute values
    //  &  Used in entity references and logical operations

    for (; index < len; index++) {
      switch (text.charCodeAt(index)) {
        case 60: // <
          entity = "&lt;";
          break;

        case 62: // >
          entity = "&gt;";
          break;

        case 34: // "
          entity = "&quot;";
          break;

        case 39: // '
          entity = "&#39;";
          break;

        case 38: // &
          entity = "&amp;";
          break;

        default:
          continue;
      }

      if (lastIndex !== index) {
        escaped += text.slice(lastIndex, index);
      }

      escaped += entity;
      lastIndex = index + 1;
    }

    if (lastIndex !== index) {
      escaped += text.slice(lastIndex, index);
    }

    return escaped;
  }

  // Based on render_dom/3
  static renderDom(dom, context, slots, defaultTarget, parentTagName) {
    if (Type.isList(dom)) {
      return Renderer.#renderNodes(
        dom,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );
    }

    const nodeType = dom.data[0].value;

    // Cases ordered by expected frequency (most common first)
    switch (nodeType) {
      case "text":
        const text = Bitstring.toText(dom.data[1]);
        return parentTagName === "script" ? text : $.escapeHtml(text);

      case "element":
        return Renderer.#renderElement(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
        );

      case "component":
        return Renderer.#renderComponent(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
        );

      case "expression":
        return $.stringifyForInterpolation(
          dom.data[1].data[0],
          parentTagName !== "script",
        );

      case "page":
        return Renderer.renderDom(
          dom.data[1],
          context,
          slots,
          Type.bitstring("page"),
          parentTagName,
        );

      case "doctype":
        return Type.nil();

      case "public_comment":
        return Renderer.#renderPublicComment(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
        );
    }
  }

  // Based on: render_page/2
  static renderPage(pageModule, pageParams) {
    const pageModuleProxy = Interpreter.moduleProxy(pageModule);

    const cid = Type.bitstring("page");
    const pageComponentStruct = ComponentRegistry.getComponentStruct(cid);

    const pageVdom = Renderer.#renderPageInsideLayout(
      pageModuleProxy,
      pageParams,
      pageComponentStruct,
    );

    const htmlVnode = pageVdom.find((vnode) => vnode.sel === "html");

    if (typeof htmlVnode === "undefined") {
      return vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, pageVdom),
      ]);
    }

    return htmlVnode;
  }

  // Based on stringify_for_interpolation/2
  static stringifyForInterpolation(value, escape = true) {
    let text;

    if (Type.isAtom(value) || Type.isBinary(value) || Type.isNumber(value)) {
      text = $.toText(value);
    } else {
      let opts;

      if (Type.isMap(value)) {
        opts = Type.keywordList([
          [
            Type.atom("custom_options"),
            Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
          ],
        ]);
      } else {
        opts = Type.list();
      }

      text = Interpreter.inspect(value, opts);
    }

    return escape ? $.escapeHtml(text) : text;
  }

  static toBitstring(term) {
    return Type.isBitstring(term) ? term : Type.bitstring($.toText(term));
  }

  // Similar to Kernel.to_string/1
  // (it is supposed to be a fast alternative to Kernel.to_string/1 for the client-side renderer only)
  // TODO: consider implementing consistency tests
  // Deps: [String.Chars.to_string/1]
  static toText(term) {
    // Cases ordered by expected frequency (most common first)
    switch (term.type) {
      case "atom":
        return term.value === "nil" ? "" : term.value;

      // Some structs (which are maps) may have their own implementation of String.Chars protocol
      case "map":
        return Bitstring.toText(Elixir_String_Chars["to_string/1"](term));

      case "bitstring":
        if (!Type.isBinary(term)) {
          Interpreter.raiseProtocolUndefinedError("String.Chars", term);
        }

        return Bitstring.toText(term);

      // String.Chars protocol has special behaviour for lists, e.g. to_string([97, 98]) -> "ab"
      case "list":
        return Bitstring.toText(Elixir_String_Chars["to_string/1"](term));

      case "integer":
        return term.value.toString();

      case "float":
        return term.value.toString();
    }

    Interpreter.raiseProtocolUndefinedError("String.Chars", term);
  }

  static valueDomToBitstring(valueDom) {
    // Cache the property access
    const valueParts = valueDom.data;

    // Early exit for empty case
    if (valueParts.length === 0) {
      return Type.bitstring("");
    }

    const bitstringChunks = new Array(valueParts.length);

    for (let i = 0; i < valueParts.length; ++i) {
      // Cache the property access
      const valuePartData = valueParts[i].data;

      if (valuePartData[0].value === "text") {
        bitstringChunks[i] = valuePartData[1];
      } else {
        bitstringChunks[i] = $.toBitstring(valuePartData[1].data[0]);
      }
    }

    return Bitstring.concat(bitstringChunks);
  }

  // Based on build_layout_props_dom/2
  // Deps: [:maps.from_list/1, :maps.merge/2]
  static #buildLayoutPropsDom(pageModuleProxy, pageState) {
    const propsFromPage = Erlang_Maps["from_list/1"](
      pageModuleProxy["__layout_props__/0"](),
    );

    const propsWithCid = Erlang_Maps["merge/2"](
      propsFromPage,
      Type.map([[Type.atom("cid"), Type.bitstring("layout")]]),
    );

    const propsWithPageState = Erlang_Maps["merge/2"](propsWithCid, pageState);

    return Type.list(
      Object.values(propsWithPageState.data).map(([name, value]) =>
        Type.tuple([
          Type.bitstring(name.value),
          Type.keywordList([[Type.atom("expression"), Type.tuple([value])]]),
        ]),
      ),
    );
  }

  // Based on cast_props/2
  // Deps: [:maps.from_list/1]
  static #castProps(propsDom, moduleProxy) {
    const propsTuples = Renderer.#filterAllowedProps(propsDom, moduleProxy)
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
  // Deps: [:lists.flatten/1]
  static #expandSlotsInNodes(nodes, slots) {
    return Erlang_Lists["flatten/1"](
      Type.list(
        nodes.data
          .filter((node) => !Type.isNil(node))
          .map((node) => Renderer.#expandSlots(node, slots)),
      ),
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
      if (valueDom.data[0].data[1].data.length === 1) {
        evaluatedValue = valueDom.data[0].data[1].data[0];
      } else {
        evaluatedValue = valueDom.data[0].data[1];
      }
    } else {
      evaluatedValue = Renderer.valueDomToBitstring(valueDom);
    }

    return Type.tuple([name, evaluatedValue]);
  }

  static #evaluateTemplate(moduleProxy, vars) {
    return Interpreter.callAnonymousFunction(moduleProxy["template/0"](), [
      vars,
    ]);
  }

  // Based on filter_allowed_props/2
  static #filterAllowedProps(propsDom, moduleProxy) {
    const registeredPropNames = Renderer.#getPropDefinitions(moduleProxy)
      .data.filter((prop) => Renderer.#contextKey(prop.data[2]) === null)
      .map((prop) => $.toBitstring(prop.data[0]));

    const allowedPropNames = registeredPropNames.concat(Type.bitstring("cid"));

    return propsDom.data.filter((propDom) =>
      allowedPropNames.some((name) =>
        Interpreter.isStrictlyEqual(name, propDom.data[0]),
      ),
    );
  }

  static #getPropDefinitions(moduleProxy) {
    if (!("__props__" in moduleProxy)) {
      moduleProxy.__props__ = moduleProxy["__props__/0"]();
    }

    return moduleProxy.__props__;
  }

  // Based on has_cid_prop?/1
  static #hasCidProp(props) {
    return "atom(cid)" in props.data;
  }

  // Based on inject_default_prop_values/2
  // Deps: [:lists.keyfind/3, :lists.keymember/3, :maps.is_key/2]
  static #injectDefaultPropValues(props, moduleProxy) {
    return Renderer.#getPropDefinitions(moduleProxy).data.reduce(
      (acc, prop) => {
        if (
          Type.isFalse(Erlang_Maps["is_key/2"](prop.data[0], acc)) &&
          Type.isTrue(
            Erlang_Lists["keymember/3"](
              Type.atom("default"),
              Type.integer(1),
              prop.data[2],
            ),
          )
        ) {
          // Optimized (mutates map)
          acc.data[Type.encodeMapKey(prop.data[0])] = [
            prop.data[0],
            Erlang_Lists["keyfind/3"](
              Type.atom("default"),
              Type.integer(1),
              prop.data[2],
            ).data[1],
          ];
        }

        return acc;
      },
      Utils.shallowCloneObject(props),
    );
  }

  // Based on inject_props_from_context/3
  // Deps: [:maps.from_list/1, :maps.get/2, :maps.merge/2]
  static #injectPropsFromContext(propsFromTemplate, moduleProxy, context) {
    const propsFromContextTuples = Renderer.#getPropDefinitions(moduleProxy)
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

  static #mapEventType(eventType) {
    return eventType.replace(/_/g, "");
  }

  // Deps: [:maps.get/2]
  static #maybeInitComponent(cid, moduleProxy, props) {
    let componentState = ComponentRegistry.getComponentState(cid);
    let componentEmittedContext;

    if (componentState === null) {
      if ("init/2" in moduleProxy) {
        const emptyComponentStruct = Type.componentStruct();

        const componentStruct = moduleProxy["init/2"](
          props,
          emptyComponentStruct,
        );

        ComponentRegistry.putEntry(
          cid,
          Type.map([
            [Type.atom("module"), moduleProxy.__exModule__],
            [Type.atom("struct"), componentStruct],
          ]),
        );

        componentState = Erlang_Maps["get/2"](
          Type.atom("state"),
          componentStruct,
        );

        componentEmittedContext = Erlang_Maps["get/2"](
          Type.atom("emitted_context"),
          componentStruct,
        );
      } else {
        const message = `component ${Interpreter.inspectModuleJsName(
          moduleProxy.__jsName__,
        )} is initialized on the client, but doesn't have init/2 implemented`;

        throw new HologramInterpreterError(message);
      }
    } else {
      componentEmittedContext =
        ComponentRegistry.getComponentEmittedContext(cid);
    }

    return [componentState, componentEmittedContext];
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
  // Deps: [:erlang.binary_to_atom/1]
  static #normalizePropName(propDom) {
    return Type.tuple([
      Erlang["binary_to_atom/1"](propDom.data[0]),
      propDom.data[1],
    ]);
  }

  // Based on render_attribute/2
  static #renderAttribute(name, valueDom) {
    const nameText = Bitstring.toText(name);

    // []
    if (valueDom.data.length === 0) {
      return [nameText, true];
    }

    // [expression: {nil}]
    if (
      valueDom.data.length === 1 &&
      Type.isTuple(valueDom.data[0].data[1]) &&
      valueDom.data[0].data[1].data.length === 1 &&
      Type.isNil(valueDom.data[0].data[1].data[0])
    ) {
      return [nameText, null];
    }

    const valueText = Renderer.#valueDomToText(valueDom);

    return [nameText, valueText === "" ? true : $.escapeHtml(valueText)];
  }

  // Based on render_attributes/1
  static #renderAttributes(attrsDom) {
    if (attrsDom.data.length === 0) {
      return {};
    }

    return attrsDom.data
      .filter((attrDom) => !Bitstring.toText(attrDom.data[0]).startsWith("$"))
      .reduce((acc, attrDom) => {
        const [nameText, valueText] = Renderer.#renderAttribute(
          attrDom.data[0],
          attrDom.data[1],
        );

        if (valueText !== null) {
          acc[nameText] = valueText;
        }

        return acc;
      }, {});
  }

  // Based on render_dom/3 (component case)
  static #renderComponent(dom, context, slots, defaultTarget, parentTagName) {
    const moduleProxy = Interpreter.moduleProxy(dom.data[1]);
    const propsDom = dom.data[2];
    let childrenDom = dom.data[3];

    const expandedChildrenDom = Renderer.#expandSlots(childrenDom, slots);

    let props = Renderer.#injectPropsFromContext(
      Renderer.#castProps(propsDom, moduleProxy),
      moduleProxy,
      context,
    );

    props = Renderer.#injectDefaultPropValues(props, moduleProxy);

    if (Renderer.#hasCidProp(props)) {
      return Renderer.#renderStatefulComponent(
        moduleProxy,
        props,
        expandedChildrenDom,
        context,
        parentTagName,
      );
    } else {
      return Renderer.#renderTemplate(
        moduleProxy,
        props,
        expandedChildrenDom,
        context,
        defaultTarget,
        parentTagName,
      );
    }
  }

  // Based on render_dom/3 (element & slot case)
  static #renderElement(dom, context, slots, defaultTarget, parentTagName) {
    const currentTagName = Bitstring.toText(dom.data[1]);

    if (currentTagName === "slot") {
      return Renderer.#renderSlotElement(
        slots,
        context,
        defaultTarget,
        parentTagName,
      );
    }

    const attrsDom = dom.data[2];
    const attrsVdom = Renderer.#renderAttributes(attrsDom);

    const eventListenersVdom = Renderer.#renderEventListeners(
      attrsDom,
      defaultTarget,
    );

    const childrenDom = dom.data[3];

    const childrenVdom = Renderer.renderDom(
      childrenDom,
      context,
      slots,
      defaultTarget,
      currentTagName,
    );

    const data = {attrs: attrsVdom, on: eventListenersVdom};

    if (
      currentTagName === "link" &&
      typeof attrsVdom.href === "string" &&
      attrsVdom.href
    ) {
      data.key = `__hologramLink__:${attrsVdom.href}`;
    } else if (
      currentTagName === "script" &&
      typeof attrsVdom.src === "string" &&
      attrsVdom.src
    ) {
      data.key = `__hologramScript__:${attrsVdom.src}`;
    } else if (currentTagName === "script" && childrenVdom[0]) {
      // Make sure the script is executed if the code changes.
      data.key = `__hologramScript__:${childrenVdom[0]}`;
    }

    return vnode(currentTagName, data, childrenVdom);
  }

  static #renderEventListeners(attrsDom, defaultTarget) {
    if (attrsDom.data.length === 0) {
      return {};
    }

    return attrsDom.data
      .filter((attrDom) => Bitstring.toText(attrDom.data[0]).startsWith("$"))
      .reduce((acc, attrDom) => {
        const nameText = $.#mapEventType(
          Bitstring.toText(attrDom.data[0]).substring(1),
        );

        acc[nameText] = (event) =>
          Hologram.handleUiEvent(
            event,
            nameText,
            attrDom.data[1],
            defaultTarget,
          );

        return acc;
      }, {});
  }

  // Based on render_dom/3 (list case)
  static #renderNodes(nodes, context, slots, defaultTarget, parentTagName) {
    return Renderer.#mergeNeighbouringTextNodes(
      nodes.data
        // There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if} or DOCTYPE
        .filter((node) => !Type.isNil(node))
        .map((node) =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          ),
        )
        .flat(),
    );
  }

  // Based on render_page_inside_layout/3
  // Deps: [:maps.get/2, :maps.merge/2]
  static #renderPageInsideLayout(
    pageModuleProxy,
    pageParams,
    pageComponentStruct,
  ) {
    const pageEmittedContext = Erlang_Maps["get/2"](
      Type.atom("emitted_context"),
      pageComponentStruct,
    );

    const pageState = Erlang_Maps["get/2"](
      Type.atom("state"),
      pageComponentStruct,
    );

    const vars = Erlang_Maps["merge/2"](pageParams, pageState);
    const pageDom = Renderer.#evaluateTemplate(pageModuleProxy, vars);

    const layoutModule = pageModuleProxy["__layout_module__/0"]();

    const layoutPropsDom = Renderer.#buildLayoutPropsDom(
      pageModuleProxy,
      pageState,
    );

    const pageNodes = Type.tuple([Type.atom("page"), pageDom]);

    const layoutNode = Type.tuple([
      Type.atom("component"),
      layoutModule,
      layoutPropsDom,
      pageNodes,
    ]);

    return Renderer.renderDom(
      layoutNode,
      pageEmittedContext,
      Type.keywordList(),
      Type.bitstring("layout"),
      null,
    );
  }

  // Based on render_dom/3 (public comment case)
  static #renderPublicComment(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
  ) {
    const childrenDom = dom.data[1];

    let childrenVdom = Renderer.renderDom(
      childrenDom,
      context,
      slots,
      defaultTarget,
      parentTagName,
    );

    const commentContent = childrenVdom
      .map((child) => (typeof child === "string" ? child : vnodeToHtml(child)))
      .join("");

    return vnode("!", commentContent);
  }

  // Based on render_dom/3 (slot case)
  static #renderSlotElement(slots, context, defaultTarget, parentTagName) {
    const slotDom = Interpreter.accessKeywordListElement(
      slots,
      Type.atom("default"),
    );

    return Renderer.renderDom(
      slotDom,
      context,
      Type.keywordList(),
      defaultTarget,
      parentTagName,
    );
  }

  // Based on render_stateful_component/4
  // Deps: [:maps.get/2, :maps.merge/2]
  static #renderStatefulComponent(
    moduleProxy,
    props,
    childrenDom,
    context,
    parentTagName,
  ) {
    const cid = Erlang_Maps["get/2"](Type.atom("cid"), props);

    const [componentState, componentEmittedContext] =
      Renderer.#maybeInitComponent(cid, moduleProxy, props);

    const vars = Erlang_Maps["merge/2"](props, componentState);
    const mergedContext = Erlang_Maps["merge/2"](
      context,
      componentEmittedContext,
    );

    return Renderer.#renderTemplate(
      moduleProxy,
      vars,
      childrenDom,
      mergedContext,
      cid,
      parentTagName,
    );
  }

  // Based on render_template/4
  static #renderTemplate(
    moduleProxy,
    vars,
    childrenDom,
    context,
    defaultTarget,
    parentTagName,
  ) {
    const dom = Renderer.#evaluateTemplate(moduleProxy, vars);
    const slots = Type.keywordList([[Type.atom("default"), childrenDom]]);

    return Renderer.renderDom(
      dom,
      context,
      slots,
      defaultTarget,
      parentTagName,
    );
  }

  static #valueDomToText(valueDom) {
    return Bitstring.toText(Renderer.valueDomToBitstring(valueDom));
  }
}

const $ = Renderer;
