"use strict";

import Bitstring from "./bitstring.mjs";
import Erlang_Maps from "./erlang/maps.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";

export default class Operation {
  constructor(specDom, defaultTarget, eventParam) {
    if (Operation.#isTextSyntax(specDom)) {
      this.constructFromTextSyntaxSpec(specDom, defaultTarget, eventParam);
    } else if (Operation.#isExpressionShorthandSyntax(specDom)) {
      this.constructFromExpressionShorthandSyntaxSpec(
        specDom,
        defaultTarget,
        eventParam,
      );
    } else if (Operation.#isExpressionLonghandSyntax(specDom)) {
      this.constructFromExpressionLonghandSyntaxSpec(
        specDom,
        defaultTarget,
        eventParam,
      );
    } else {
      this.constructFromMultiChunkSyntaxSpec(
        specDom,
        defaultTarget,
        eventParam,
      );
    }
  }

  // deps: [:maps.from_list/1, :maps.put/3]
  buildParamsMap(paramsKeywordList, eventParam) {
    this.params = Erlang_Maps["put/3"](
      Type.atom("event"),
      eventParam,
      Erlang_Maps["from_list/1"](paramsKeywordList),
    );
  }

  constructFromExpressionLonghandSyntaxSpec(
    specDom,
    defaultTarget,
    eventParam,
  ) {
    const target = Interpreter.accessKeywordListElement(
      specDom.data[0].data[1].data[0],
      Type.atom("target"),
    );

    this.target = target ? target : defaultTarget;

    this.resolveNameAndType(specDom, defaultTarget);

    const paramsKeywordList =
      Interpreter.accessKeywordListElement(
        specDom.data[0].data[1].data[0],
        Type.atom("params"),
      ) || Type.keywordList([]);

    this.buildParamsMap(paramsKeywordList, eventParam);
  }

  constructFromExpressionShorthandSyntaxSpec(
    specDom,
    defaultTarget,
    eventParam,
  ) {
    this.name = specDom.data[0].data[1].data[0];
    this.target = defaultTarget;
    this.type = "action";

    const paramsKeywordList =
      specDom.data[0].data[1].data[1] || Type.keywordList([]);

    this.buildParamsMap(paramsKeywordList, eventParam);
  }

  // $click="aaa{123}bbb"
  constructFromMultiChunkSyntaxSpec(specDom, defaultTarget, eventParam) {
    const nameBitstring = Renderer.valueDomToBitstring(specDom);
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), eventParam]]);
    this.target = defaultTarget;
    this.type = "action";
  }

  constructFromTextSyntaxSpec(specDom, defaultTarget, eventParam) {
    const nameBitstring = specDom.data[0].data[1];
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.params = Type.map([[Type.atom("event"), eventParam]]);
    this.target = defaultTarget;
    this.type = "action";
  }

  resolveNameAndType(specDom, defaultTarget) {
    const action = Interpreter.accessKeywordListElement(
      specDom.data[0].data[1].data[0],
      Type.atom("action"),
    );

    if (action) {
      this.name = action;
      this.type = "action";
      return;
    }

    const command = Interpreter.accessKeywordListElement(
      specDom.data[0].data[1].data[0],
      Type.atom("command"),
    );

    if (command) {
      this.name = command;
      this.type = "command";
      return;
    }

    throw new HologramInterpreterError(
      `Operation spec is invalid: "${Interpreter.inspect(specDom.data[0].data[1])}". See what to do here: https://www.hologram.page/TODO`,
    );
  }

  // $click={action: :my_action, params: [a: 1, b: 2]}
  static #isExpressionLonghandSyntax(specDom) {
    return (
      specDom.data.length === 1 &&
      specDom.data[0].data[0].value === "expression" &&
      Type.isList(specDom.data[0].data[1].data[0])
    );
  }

  // $click={:my_action, a: 1, b: 2}
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
