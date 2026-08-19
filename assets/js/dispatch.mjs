"use strict";

import Bitstring from "./bitstring.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";

// What an event binding makes when its event fires - an action, run on the client, or a
// command, run on the server. The class parses the binding's spec into the boxed struct the
// runtime dispatches, in each of the syntaxes a template may write it in.
//
// Named for what it produces rather than what it is: "operation" is the data layer's word for
// a policy verb (`can?(user, :archive, doc)`), and since the permission check is evaluated on
// the client both senses would otherwise live in one bundle.
export default class Dispatch {
  #defaultTarget;
  #eventParam;
  #specDom;

  static fromSpecDom(specDom, defaultTarget, eventParam) {
    const dispatch = new Dispatch();

    dispatch.#defaultTarget = defaultTarget;
    dispatch.#eventParam = eventParam;
    dispatch.#specDom = specDom;

    if (Dispatch.#isTextSyntax(specDom)) {
      dispatch.#constructFromTextSyntaxSpec();
    } else if (Dispatch.#isExpressionShorthandSyntax(specDom)) {
      dispatch.#constructFromExpressionShorthandSyntaxSpec();
    } else if (Dispatch.#isExpressionLonghandSyntax(specDom)) {
      return dispatch.#constructFromExpressionLonghandSyntaxSpec(specDom);
    } else {
      dispatch.#constructFromMultiChunkSyntaxSpec();
    }

    return Type.actionStruct({
      name: dispatch.name,
      params: dispatch.params,
      target: dispatch.target,
      delay: dispatch.delay,
    });
  }

  // Deps: [:maps.get/2]
  static isAction(dispatch) {
    return (
      Erlang_Maps["get/2"](Type.atom("__struct__"), dispatch).value ===
      "Elixir.Hologram.Component.Action"
    );
  }

  // An event binding is disabled when its dispatch name resolves to nil: the whole value
  // (e.g. $click={nil}), the shorthand name slot (e.g. $click={nil, a: 1}), or the longhand
  // action/command key (e.g. $click={action: nil}). The longhand branch mirrors the name
  // resolution in #constructFromExpressionLonghandSyntaxSpec, so this predicate and the
  // dispatch itself can never disagree on which key names it.
  static isDisabled(specDom) {
    if (Dispatch.#isExpressionShorthandSyntax(specDom)) {
      return Type.isNil(specDom.data[0].data[1].data[0]);
    }

    if (Dispatch.#isExpressionLonghandSyntax(specDom)) {
      const specKeywordList = specDom.data[0].data[1].data[0];

      const actionName = Interpreter.accessKeywordListElement(
        specKeywordList,
        Type.atom("action"),
      );

      const name = actionName
        ? actionName
        : Interpreter.accessKeywordListElement(
            specKeywordList,
            Type.atom("command"),
          );

      return name === null || Type.isNil(name);
    }

    return false;
  }

  // Deps: [:maps.from_list/1, :maps.put/3]
  #buildParamsMap(paramsKeywordList) {
    this.params = Erlang_Maps["put/3"](
      Type.atom("event"),
      this.#eventParam,
      Erlang_Maps["from_list/1"](paramsKeywordList),
    );
  }

  // Example: $click={action: :my_action, target: "my_target", params: %{a: 1, b: 2}}
  // Spec DOM: [expression: {[action: :my_action, target: "my_target", params: %{a: 1, b: 2}]}],
  // which is equivalent to [{:expression, {[{:action, :my_action}, {:target, "my_target"}, {:params, %{a: 1, b: 2}}]}}]
  // Deps: [:maps.put/3]
  #constructFromExpressionLonghandSyntaxSpec(specDom) {
    const specKeywordList = specDom.data[0].data[1].data[0];

    const actionName = Interpreter.accessKeywordListElement(
      specKeywordList,
      Type.atom("action"),
    );

    const name = actionName
      ? actionName
      : Interpreter.accessKeywordListElement(
          specKeywordList,
          Type.atom("command"),
        );

    const params = Erlang_Maps["put/3"](
      Type.atom("event"),
      this.#eventParam,
      Interpreter.accessKeywordListElement(
        specKeywordList,
        Type.atom("params"),
        Type.map(),
      ),
    );

    const target = Interpreter.accessKeywordListElement(
      specKeywordList,
      Type.atom("target"),
      this.#defaultTarget,
    );

    const delay = Interpreter.accessKeywordListElement(
      specKeywordList,
      Type.atom("delay"),
      Type.integer(0),
    );

    if (actionName) {
      return Type.actionStruct({
        name: name,
        params: params,
        target: target,
        delay: delay,
      });
    } else {
      if (!Interpreter.isStrictlyEqual(delay, Type.integer(0))) {
        throw new HologramInterpreterError(
          "Command delay is not yet implemented in Hologram",
        );
      }

      return Type.commandStruct({name: name, params: params, target: target});
    }
  }

  // Example: $click={:my_action, a: 1, b: 2}
  // Spec DOM: [expression: {:my_action, a: 1, b: 2}],
  // which is equivalent to [{:expression, {:my_action, [{:a, 1}, {:b, 2}]}}]
  #constructFromExpressionShorthandSyntaxSpec() {
    this.name = this.#specDom.data[0].data[1].data[0];
    this.target = this.#defaultTarget;
    this.delay = Type.integer(0);

    const paramsKeywordList =
      this.#specDom.data[0].data[1].data[1] || Type.keywordList();

    this.#buildParamsMap(paramsKeywordList);
  }

  // Example: $click="aaa{123}bbb"
  // Spec DOM: [text: "aaa", expression: {123}, text: "bbb"],
  // which is equivalent to [{:text, "aaa"}, {:expression, {123}}, {:text, "bbb"}]
  #constructFromMultiChunkSyntaxSpec() {
    const nameBitstring = Renderer.valueDomToBitstring(this.#specDom);
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), this.#eventParam]]);
    this.target = this.#defaultTarget;
    this.delay = Type.integer(0);
  }

  // Example: $click="my_action"
  // Spec DOM: [text: "my_action"], which is equivalent to [{:text, "my_action"}]
  #constructFromTextSyntaxSpec() {
    const nameBitstring = this.#specDom.data[0].data[1];
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), this.#eventParam]]);
    this.target = this.#defaultTarget;
    this.delay = Type.integer(0);
  }

  // Example: $click={action: :my_action, target: "my_target", params: %{a: 1, b: 2}}
  // Spec DOM: [expression: {[action: :my_action, target: "my_target", params: %{a: 1, b: 2}]}],
  // which is equivalent to [{:expression, {[{:action, :my_action}, {:target, "my_target"}, {:params, %{a: 1, b: 2}}]}}]
  static #isExpressionLonghandSyntax(specDom) {
    return (
      specDom.data.length === 1 &&
      specDom.data[0].data[0].value === "expression" &&
      Type.isList(specDom.data[0].data[1].data[0])
    );
  }

  // Example: $click={:my_action, a: 1, b: 2}
  // Spec DOM: [expression: {:my_action, a: 1, b: 2}],
  // which is equivalent to [{:expression, {:my_action, [{:a, 1}, {:b, 2}]}}]
  static #isExpressionShorthandSyntax(specDom) {
    return (
      specDom.data.length === 1 &&
      specDom.data[0].data[0].value === "expression" &&
      Type.isAtom(specDom.data[0].data[1].data[0])
    );
  }

  // Example: $click="my_action"
  // Spec DOM: [text: "my_action"], which is equivalent to [{:text, "my_action"}]
  static #isTextSyntax(specDom) {
    return (
      specDom.data.length === 1 && specDom.data[0].data[0].value === "text"
    );
  }
}
