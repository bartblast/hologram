"use strict";

import Bitstring from "./bitstring.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";

export default class Operation {
  constructor(specDom, defaultTarget, eventParam) {
    this.defaultTarget = defaultTarget;
    this.eventParam = eventParam;
    this.specDom = specDom;

    if (Operation.#isTextSyntax(specDom)) {
      this.#constructFromTextSyntaxSpec();
    } else if (Operation.#isExpressionShorthandSyntax(specDom)) {
      this.#constructFromExpressionShorthandSyntaxSpec();
    } else if (Operation.#isExpressionLonghandSyntax(specDom)) {
      this.#constructFromExpressionLonghandSyntaxSpec();
    } else {
      this.#constructFromMultiChunkSyntaxSpec();
    }
  }

  // deps: [:maps.from_list/1, :maps.put/3]
  #buildParamsMap(paramsKeywordList) {
    this.params = Erlang_Maps["put/3"](
      Type.atom("event"),
      this.eventParam,
      Erlang_Maps["from_list/1"](paramsKeywordList),
    );
  }

  #constructFromExpressionLonghandSyntaxSpec() {
    const target = Interpreter.accessKeywordListElement(
      this.specDom.data[0].data[1].data[0],
      Type.atom("target"),
    );

    this.target = target ? target : this.defaultTarget;

    this.#resolveNameAndType();

    const paramsKeywordList =
      Interpreter.accessKeywordListElement(
        this.specDom.data[0].data[1].data[0],
        Type.atom("params"),
      ) || Type.keywordList([]);

    this.#buildParamsMap(paramsKeywordList);
  }

  #constructFromExpressionShorthandSyntaxSpec() {
    this.name = this.specDom.data[0].data[1].data[0];
    this.target = this.defaultTarget;
    this.type = "action";

    const paramsKeywordList =
      this.specDom.data[0].data[1].data[1] || Type.keywordList([]);

    this.#buildParamsMap(paramsKeywordList);
  }

  // Example: $click="aaa{123}bbb"
  #constructFromMultiChunkSyntaxSpec() {
    const nameBitstring = Renderer.valueDomToBitstring(this.specDom);
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), this.eventParam]]);
    this.target = this.defaultTarget;
    this.type = "action";
  }

  #constructFromTextSyntaxSpec() {
    const nameBitstring = this.specDom.data[0].data[1];
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), this.eventParam]]);
    this.target = this.defaultTarget;
    this.type = "action";
  }

  #resolveNameAndType() {
    const action = Interpreter.accessKeywordListElement(
      this.specDom.data[0].data[1].data[0],
      Type.atom("action"),
    );

    if (action) {
      this.name = action;
      this.type = "action";
      return;
    }

    const command = Interpreter.accessKeywordListElement(
      this.specDom.data[0].data[1].data[0],
      Type.atom("command"),
    );

    if (command) {
      this.name = command;
      this.type = "command";
      return;
    }

    throw new HologramInterpreterError(
      `Operation spec is invalid: "${Interpreter.inspect(this.specDom.data[0].data[1])}". See what to do here: https://www.hologram.page/TODO`,
    );
  }

  // Example: $click={action: :my_action, params: [a: 1, b: 2]}
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
