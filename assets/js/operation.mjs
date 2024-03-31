"use strict";

import Bitstring from "./bitstring.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";

export default class Operation {
  constructor(specDom, defaultTarget, _eventParam) {
    // this.target = Operation.#resolveTarget(specDom, defaultTarget)
    // this.params = Operation.#resolveParams(specDom, eventParam)

    if (Operation.#isTextSyntax(specDom)) {
      this.constructFromTextSyntaxSpec(specDom, defaultTarget);
    } else if (Operation.#isExpressionShorthandSyntax(specDom)) {
      this.constructFromExpressionShorthandSyntaxSpec(specDom, defaultTarget);
    } else if (Operation.#isExpressionLonghandSyntax(specDom)) {
      this.constructFromExpressionLonghandSyntaxSpec(specDom, defaultTarget);
    } else {
      this.constructFromMultiChunkSyntaxSpec(specDom, defaultTarget);
    }
  }

  constructFromExpressionLonghandSyntaxSpec(specDom, defaultTarget) {
    const target = Interpreter.accessKeywordListElement(
      specDom.data[0].data[1].data[0],
      Type.atom("target"),
    );

    this.target = target ? target : defaultTarget;

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

  constructFromExpressionShorthandSyntaxSpec(specDom, defaultTarget) {
    this.name = specDom.data[0].data[1].data[0];
    this.target = defaultTarget;
    this.type = "action";
  }

  // $click="aaa{123}bbb"
  constructFromMultiChunkSyntaxSpec(specDom, defaultTarget) {
    const nameBitstring = Renderer.valueDomToBitstring(specDom);
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.target = defaultTarget;
    this.type = "action";
  }

  constructFromTextSyntaxSpec(specDom, defaultTarget) {
    const nameBitstring = specDom.data[0].data[1];
    const nameText = Bitstring.toText(nameBitstring);

    this.name = Type.atom(nameText);
    this.target = defaultTarget;
    this.type = "action";
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
