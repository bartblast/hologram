"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import ERTS from "../../assets/js/erts.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ERTS", () => {
  describe("uniqueReference()", () => {
    it("returns a reference", () => {
      const result = ERTS.uniqueReference();

      assert.isTrue(Type.isReference(result));
    });

    it("uses the client node", () => {
      const result = ERTS.uniqueReference();

      assert.strictEqual(result.node, ERTS.nodeTable.CLIENT_NODE);
    });

    it("consecutive calls return unique references", () => {
      const ref1 = ERTS.uniqueReference();
      const ref2 = ERTS.uniqueReference();

      assert.isFalse(Interpreter.isEqual(ref1, ref2));
    });
  });
});
