// Based on Elixir Hologram.Template.Renderer

"use strict";

import Bitstring from "./bitstring.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Hologram from "./hologram.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import InitActionQueue from "./init_action_queue.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

import {h as vnode} from "snabbdom";
import vnodeToHtml from "snabbdom-to-html";

export default class Renderer {
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
        return Bitstring.toText(dom.data[1]);

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
        // HTML escaping is done by Snabbdom
        return $.toText(dom.data[1].data[0]);

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

  static toBitstring(term) {
    return Type.isBitstring(term) ? term : Type.bitstring($.toText(term));
  }

  // Similar to Kernel.to_string/1
  // (it is supposed to be a fast alternative to Kernel.to_string/1 for the client-side renderer only)
  // Deps: [String.Chars.to_string/1]
  static toText(term) {
    // Cases ordered by expected frequency (most common first)
    switch (term.type) {
      case "atom":
        return term.value === "nil" ? "" : term.value;

      case "bitstring":
        if (Type.isBinary(term)) {
          return Bitstring.toText(term);
        }
        break;

      case "integer":
      case "float":
        return term.value.toString();
    }

    return Bitstring.toText(Elixir_String_Chars["to_string/1"](term));
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
        // expression
        const expressionText = $.toText(valuePartData[1].data[0]);

        bitstringChunks[i] = Type.bitstring(expressionText);
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

  static #determineInputType(tagName, attrs) {
    let typeAttr;

    switch (tagName) {
      case "input":
        typeAttr = attrs.find(([name, _valueDom]) => name === "type");
        return typeAttr ? Renderer.#valueDomToText(typeAttr[1]) : "text";

      case "select":
        return "select";

      case "textarea":
        return "textarea";
    }

    return null;
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
  // Deps: [:maps.from_list/1, :maps.get/2, :maps.is_key/2, :maps.merge/2]
  static #injectPropsFromContext(propsFromTemplate, moduleProxy, context) {
    const propsFromContextTuples = Renderer.#getPropDefinitions(moduleProxy)
      .data.filter((prop) => {
        const contextKey = Renderer.#contextKey(prop.data[2]);
        return (
          contextKey !== null &&
          Type.isTrue(Erlang_Maps["is_key/2"](contextKey, context))
        );
      })
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

  static #isControlledValueInputType(inputType) {
    // Control value for all input types except radio and checkbox
    // Radios and checkboxes use value attribute for submit value, not display value
    // Also control value for textarea and select elements
    return inputType !== "checkbox" && inputType !== "radio";
  }

  static #mapEventName(eventName, tagName, attrsVdom) {
    if (eventName === "change") {
      if (tagName === "input") {
        const inputType = attrsVdom?.type || "text";

        if (inputType !== "checkbox" && inputType !== "radio") {
          return "input";
        }
      } else if (tagName === "textarea") {
        return "input";
      }

      // Select elements keep the original change event (no mapping needed)
    }

    return eventName;
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

        Renderer.#maybeQueueActionFromClientInit(componentStruct, cid);
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

  // Deps: [:maps.get/2, :maps.get/3, :maps.put/3]
  static #maybeQueueActionFromClientInit(componentStruct, cid) {
    const nextAction = Erlang_Maps["get/2"](
      Type.atom("next_action"),
      componentStruct,
    );

    if (!Type.isNil(nextAction)) {
      let actionWithTarget = nextAction;

      const existingTarget = Erlang_Maps["get/3"](
        Type.atom("target"),
        nextAction,
        Type.nil(),
      );

      if (Type.isNil(existingTarget)) {
        actionWithTarget = Erlang_Maps["put/3"](
          Type.atom("target"),
          cid,
          nextAction,
        );
      }

      InitActionQueue.enqueue(actionWithTarget);
    }
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

  static #normalizeEventName(eventName) {
    return eventName.replace(/_/g, "");
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
  static #renderAttribute(
    name,
    valueDom,
    isControlledValueAttr,
    isControlledCheckedAttr,
  ) {
    // Handle empty attribute: []
    if (valueDom.data.length === 0) {
      return [name, true];
    }

    // Handle single expressions: [expression: {value}]
    if (
      valueDom.data.length === 1 &&
      Type.isTuple(valueDom.data[0].data[1]) &&
      valueDom.data[0].data[1].data.length === 1
    ) {
      const expressionValue = valueDom.data[0].data[1].data[0];

      // Checkbox & radio checked attribute: preserve boolean semantics
      if (isControlledCheckedAttr) {
        return [name, Type.isTruthy(expressionValue)];
      }

      // Other attributes: nil/false removes the attribute
      if (Type.isFalsy(expressionValue)) {
        return [name, null];
      }
    }

    // Convert to text for remaining cases
    const valueText = Renderer.#valueDomToText(valueDom);

    // Input value attribute: preserve strings (including empty strings)
    if (isControlledValueAttr) {
      return [name, valueText];
    }

    // Checkbox & radio checked attribute: everything else is truthy (HTML-like behavior)
    if (isControlledCheckedAttr) {
      return [name, true];
    }

    // Other attributes: empty string becomes boolean true
    return [name, valueText === "" ? true : valueText];
  }

  // Based on render_attributes/1
  // "props" are Snabbdom props, not Hologram component props
  static #renderAttributesAndProps(attrsDom, tagName) {
    const attrs = {};
    const props = {};

    if (attrsDom.data.length === 0) {
      return {attrs, props};
    }

    // Unbox name and filter out event attributes (starting with $) in single loop pass
    const regularAttrs = attrsDom.data.reduce((acc, attrDom) => {
      const name = Bitstring.toText(attrDom.data[0]);

      if (!name.startsWith("$")) {
        acc.push([name, attrDom.data[1]]);
      }

      return acc;
    }, []);

    // Check if this is a form element with special handling of checked and value attributes
    const isFormInput =
      tagName === "input" || tagName === "textarea" || tagName === "select";

    let inputType;
    if (isFormInput) {
      inputType = $.#determineInputType(tagName, regularAttrs);
    }

    for (const [name, valueDom] of regularAttrs) {
      // Text-based inputs should have controlled value behavior
      // Radio and checkbox inputs use their value attribute as a regular HTML attribute
      let isControlledCheckedAttr, isControlledValueAttr;

      if (isFormInput) {
        if (name === "value" && $.#isControlledValueInputType(inputType)) {
          isControlledValueAttr = true;
        } else if (name === "checked" && tagName === "input") {
          isControlledCheckedAttr = true;
        }
      }

      const [, valueText] = Renderer.#renderAttribute(
        name,
        valueDom,
        isControlledValueAttr,
        isControlledCheckedAttr,
      );

      if (valueText !== null) {
        // For form element values: only set the property, never the attribute to maintain proper form behavior
        // - Preserves the browser's dirty flag tracking
        // - Ensures correct form reset behavior (resets to original defaultValue)
        // - Maintains proper autocomplete/autofill behavior
        // See: https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#concept-fe-dirty
        if (isControlledValueAttr) {
          // Store the value for later use in hooks
          attrs["data-hologram-form-input-value"] = valueText;
        } else if (isControlledCheckedAttr) {
          // Store the checked state for later use in hooks
          attrs["data-hologram-form-input-checked"] = valueText;
        } else {
          attrs[name] = valueText;
        }
      }
    }

    return {attrs, props};
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

    const {attrs: attrsVdom, props: propsVdom} =
      Renderer.#renderAttributesAndProps(attrsDom, currentTagName);

    const eventListenersVdom = Renderer.#renderEventListeners(
      attrsDom,
      currentTagName,
      attrsVdom,
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

    if (Object.keys(propsVdom).length > 0) {
      data.props = propsVdom;
    }

    // Handle controlled form inputs (value for text inputs/textareas/selects, checked for checkboxes/radios)
    // Radio/checkbox inputs use regular value attributes and controlled checked attributes
    // An element has either controlled value OR controlled checked, never both

    if (
      (currentTagName === "input" ||
        currentTagName === "textarea" ||
        currentTagName === "select") &&
      attrsVdom["data-hologram-form-input-value"] !== undefined
    ) {
      const hologramFormInputValue =
        attrsVdom["data-hologram-form-input-value"];
      delete attrsVdom["data-hologram-form-input-value"];
      data.hologramFormInputValue = hologramFormInputValue;

      data.hook = {
        create: (_emptyVnode, newVnode) => {
          Renderer.#updateFormInputValue(newVnode.elm, hologramFormInputValue);
        },
        update: (_oldVnode, newVnode) => {
          const newValue = newVnode.data.hologramFormInputValue;
          Renderer.#updateFormInputValue(newVnode.elm, newValue);
        },
      };
    } else if (
      currentTagName === "input" &&
      attrsVdom["data-hologram-form-input-checked"] !== undefined
    ) {
      const hologramFormInputChecked =
        attrsVdom["data-hologram-form-input-checked"];
      delete attrsVdom["data-hologram-form-input-checked"];
      data.hologramFormInputChecked = hologramFormInputChecked;

      data.hook = {
        create: (_emptyVnode, newVnode) => {
          Renderer.#updateFormInputChecked(
            newVnode.elm,
            hologramFormInputChecked,
          );
        },
        update: (_oldVnode, newVnode) => {
          const newChecked = newVnode.data.hologramFormInputChecked;
          Renderer.#updateFormInputChecked(newVnode.elm, newChecked);
        },
      };
    }

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

  static #renderEventListeners(attrsDom, tagName, attrsVdom, defaultTarget) {
    if (attrsDom.data.length === 0) {
      return {};
    }

    return attrsDom.data.reduce((acc, attrDom) => {
      const attributeName = Bitstring.toText(attrDom.data[0]);

      if (!attributeName.startsWith("$")) {
        return acc;
      }

      const originalEventName = attributeName.substring(1);
      const normalizedEventName = $.#normalizeEventName(originalEventName);

      const effectiveDomEventName = $.#mapEventName(
        normalizedEventName,
        tagName,
        attrsVdom,
      );

      acc[effectiveDomEventName] = (event) =>
        Hologram.handleUiEvent(
          event,
          effectiveDomEventName,
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

  static #updateFormInputChecked(element, newChecked) {
    // Skip redundant DOM writes
    if (newChecked === element.checked) {
      return;
    }

    element.checked = newChecked;
  }

  static #updateFormInputValue(element, newValue) {
    // Skip redundant DOM writes
    if (newValue === element.value) {
      return;
    }

    element.value = newValue;
  }

  static #valueDomToText(valueDom) {
    return Bitstring.toText(Renderer.valueDomToBitstring(valueDom));
  }
}

const $ = Renderer;
