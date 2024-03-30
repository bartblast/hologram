"use strict";

import Bitstring from "./bitstring.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Renderer from "./renderer.mjs";
import Type from "./type.mjs";

export default class Operation {
  constructor(specDom, _defaultTarget, _eventParam) {
    // this.type = Operation.#resolveType(specVdom)
    this.name = Operation.#resolveName(specDom);
    // this.target = Operation.#resolveTarget(specDom, defaultTarget)
    // this.params = Operation.#resolveParams(specDom, eventParam)
  }

  static #resolveName(specDom) {
    if (specDom.data.length > 1) {
      // $click="aaa{123}bbb"
      const nameBitstring = Renderer.valueDomToBitstring(specDom);
      const nameText = Bitstring.toText(nameBitstring);
      return Type.atom(nameText);
    } else if (specDom.data[0].data[0].value === "text") {
      // $click="my_action"
      const nameBitstring = specDom.data[0].data[1];
      const nameText = Bitstring.toText(nameBitstring);
      return Type.atom(nameText);
    } else if (
      specDom.data[0].data[0].value === "expression" &&
      Type.isAtom(specDom.data[0].data[1].data[0])
    ) {
      // $click={:my_action, a: 1, b: 2}
      return specDom.data[0].data[1].data[0];
    } else {
      // $click={action: :my_action, params: [a: 1, b: 2]}
      const action = Interpreter.accessKeywordListElement(
        specDom.data[0].data[1].data[0],
        Type.atom("action"),
      );

      if (action) {
        return action;
      }

      // $click={command: :my_command, params: [a: 1, b: 2]}
      const command = Interpreter.accessKeywordListElement(
        specDom.data[0].data[1].data[0],
        Type.atom("command"),
      );

      if (command) {
        return command;
      }

      throw new HologramInterpreterError(
        `Can't resolve operation name in: "${Interpreter.inspect(specDom.data[0].data[1])}". See what to do here: https://www.hologram.page/TODO`,
      );
    }
  }
}
