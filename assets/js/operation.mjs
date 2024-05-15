"use strict";

import Bitstring from "./bitstring.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
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
      operation.#constructFromExpressionLonghandSyntaxSpec();
    } else {
      operation.#constructFromMultiChunkSyntaxSpec();
    }

    const structAliasString =
      operation.type.value === "action"
        ? "Hologram.Component.Action"
        : "Hologram.Component.Command";

    return Type.struct(structAliasString, [
      [Type.atom("name"), operation.name],
      [Type.atom("params"), operation.params],
      [Type.atom("target"), operation.target],
    ]);
  }

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

  #constructFromExpressionLonghandSyntaxSpec() {
    this.name = Interpreter.accessKeywordListElement(
      this.#specDom.data[0].data[1].data[0],
      Type.atom("name"),
    );

    if (this.name === null) {
      throw new HologramInterpreterError(
        `Operation spec is invalid: "${Interpreter.inspect(this.#specDom.data[0].data[1])}". See what to do here: https://www.hologram.page/TODO`,
      );
    }

    const paramsKeywordList =
      Interpreter.accessKeywordListElement(
        this.#specDom.data[0].data[1].data[0],
        Type.atom("params"),
      ) || Type.keywordList([]);

    this.#buildParamsMap(paramsKeywordList);

    const target = Interpreter.accessKeywordListElement(
      this.#specDom.data[0].data[1].data[0],
      Type.atom("target"),
    );

    this.target = target ? target : this.#defaultTarget;

    const type = Interpreter.accessKeywordListElement(
      this.#specDom.data[0].data[1].data[0],
      Type.atom("type"),
    );

    if (type) {
      this.type = type;
    } else {
      this.type = Type.atom("action");
    }
  }

  #constructFromExpressionShorthandSyntaxSpec() {
    this.name = this.#specDom.data[0].data[1].data[0];
    this.target = this.#defaultTarget;
    this.type = Type.atom("action");

    const paramsKeywordList =
      this.#specDom.data[0].data[1].data[1] || Type.keywordList([]);

    this.#buildParamsMap(paramsKeywordList);
  }

  // Example: $click="aaa{123}bbb"
  #constructFromMultiChunkSyntaxSpec() {
    const nameBitstring = Renderer.valueDomToBitstring(this.#specDom);
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), this.#eventParam]]);
    this.target = this.#defaultTarget;
    this.type = Type.atom("action");
  }

  #constructFromTextSyntaxSpec() {
    const nameBitstring = this.#specDom.data[0].data[1];
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), this.#eventParam]]);
    this.target = this.#defaultTarget;
    this.type = Type.atom("action");
  }

  // Example: $click={name: :my_action, params: [a: 1, b: 2]}
  static #isExpressionLonghandSyntax(specDom) {
    return (
      specDom.data.length === 1 &&
      specDom.data[0].data[0].value === "expression" &&
      Type.isList(specDom.data[0].data[1].data[0])
    );
  }

  // Example: $click={:my_action, a: 1, b: 2}
  static #isExpressionShorthandSyntax(specDom) {
    return (
      specDom.data.length === 1 &&
      specDom.data[0].data[0].value === "expression" &&
      Type.isAtom(specDom.data[0].data[1].data[0])
    );
  }

  // Example: $click="my_action"
  static #isTextSyntax(specDom) {
    return (
      specDom.data.length === 1 && specDom.data[0].data[0].value === "text"
    );
  }
}
