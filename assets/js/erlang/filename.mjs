"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Erlang_Filename = {
  // Start basename/1
  "basename/1": (atomOrBinaryOrList) => {
    if (Type.isList(atomOrBinaryOrList)) {
      if (atomOrBinaryOrList.data.length === 0) {
        return Type.list([]);
      }

      const binary = Erlang["iolist_to_binary/1"](atomOrBinaryOrList);
      Bitstring.maybeSetTextFromBytes(binary);
      const parts = binary.text.split("/").filter((part) => part !== "");
      const basenameText = parts.length > 0 ? parts[parts.length - 1] : "";
      const basenameBinary = Type.bitstring(basenameText);
      return Bitstring.toCodepoints(basenameBinary);
    }

    if (
      Type.isBitstring(atomOrBinaryOrList) &&
      !Type.isBinary(atomOrBinaryOrList)
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          atomOrBinaryOrList,
          Type.list([]),
        ]),
      );
    }

    if (
      Type.isTuple(atomOrBinaryOrList) ||
      (!Type.isAtom(atomOrBinaryOrList) && !Type.isBinary(atomOrBinaryOrList))
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          atomOrBinaryOrList,
          Type.list([]),
        ]),
      );
    }

    const isAtom = Type.isAtom(atomOrBinaryOrList);
    let binary = isAtom
      ? Erlang["atom_to_binary/1"](atomOrBinaryOrList)
      : atomOrBinaryOrList;

    Bitstring.maybeSetTextFromBytes(binary);
    const parts = binary.text.split("/").filter((part) => part !== "");
    const basenameText = parts.length > 0 ? parts[parts.length - 1] : "";
    const basenameBinary = Type.bitstring(basenameText);

    if (isAtom) {
      return Bitstring.toCodepoints(basenameBinary);
    }

    return basenameBinary;
  },
  // End basename/1
  // Deps: [:erlang.atom_to_binary/1, :erlang.iolist_to_binary/1]
};

export default Erlang_Filename;
