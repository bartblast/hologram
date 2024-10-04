"use strict";

import Bitstring from "./bitstring.mjs";
import Interpreter from "./interpreter.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";

export default class Operation {
  #defaultTarget;
  #eventParam;
  #specDom;

  static fromSpecDom(specDom, defaultTarget, eventParam) {
    const operation = new Operation();

    operation.#defaultTarget = defaultTarget;
    operation.#eventParam = eventParam;
    operation.#specDom = specDom;

    if (Operation.#isTextSyntax(specDom)) {
      operation.#constructFromTextSyntaxSpec();
    } else if (Operation.#isExpressionShorthandSyntax(specDom)) {
      operation.#constructFromExpressionShorthandSyntaxSpec();
    } else if (Operation.#isExpressionLonghandSyntax(specDom)) {
      return operation.#constructFromExpressionLonghandSyntaxSpec(specDom);
    } else {
      operation.#constructFromMultiChunkSyntaxSpec();
    }

    return Type.actionStruct({
      name: operation.name,
      params: operation.params,
      target: operation.target,
    });
  }

  // Deps: [:maps.get/2]
  static isAction(operation) {
    return (
      Erlang_Maps["get/2"](Type.atom("__struct__"), operation).value ===
      "Elixir.Hologram.Component.Action"
    );
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

    const opStructBuilder = actionName ? Type.actionStruct : Type.commandStruct;

    return opStructBuilder({name: name, params: params, target: target});
  }

  // Example: $click={:my_action, a: 1, b: 2}
  // Spec DOM: [expression: {:my_action, a: 1, b: 2}],
  // which is equivalent to [{:expression, {:my_action, [{:a, 1}, {:b, 2}]}}]
  #constructFromExpressionShorthandSyntaxSpec() {
    this.name = this.#specDom.data[0].data[1].data[0];
    this.target = this.#defaultTarget;

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
  }

  // Example: $click="my_action"
  // Spec DOM: [text: "my_action"], which is equivalent to [{:text, "my_action"}]
  #constructFromTextSyntaxSpec() {
    const nameBitstring = this.#specDom.data[0].data[1];
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), this.#eventParam]]);
    this.target = this.#defaultTarget;
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
