"use strict";

import {assert} from "chai";
import Erlang from "./erlang/erlang.mjs";
import Erlang_maps from "./erlang/maps.mjs";
import Hologram from "./hologram.mjs";
import sinonESM from "../node_modules/sinon/pkg/sinon-esm.js";
import Type from "./type.mjs";

import $243 from "./erlang/$243.mjs";
import $245 from "./erlang/$245.mjs";
import $261$261 from "./erlang/$261$261.mjs";

function buildElixirKernelInspectFunction() {
  return (term) => {
    switch (term.type) {
      // TODO: handle correctly atoms which need to be double quoted, e.g. :"1"
      case "atom":
        if (Type.isBoolean(term) || Type.isNil(term)) {
          return term.value;
        }
        return ":" + term.value;

      // TODO: case "bitstring"

      case "float":
        if (Number.isInteger(term.value)) {
          return term.value.toString() + ".0";
        } else {
          return term.value.toString();
        }

      case "integer":
        return term.value.toString();

      case "list":
        if (term.isProper) {
          return (
            "[" +
            term.data.map((item) => Elixir_Kernel.inspect(item)).join(", ") +
            "]"
          );
        } else {
          return (
            "[" +
            term.data
              .slice(0, -1)
              .map((item) => Elixir_Kernel.inspect(item))
              .join(", ") +
            " | " +
            Elixir_Kernel.inspect(term.data.slice(-1)[0]) +
            "]"
          );
        }

      case "string":
        return '"' + term.value.toString() + '"';

      case "tuple":
        return (
          "{" +
          term.data.map((item) => Elixir_Kernel.inspect(item)).join(", ") +
          "}"
        );

      default:
        return Hologram.serialize(term);
    }
  };
}

// This version of Elixir_Kernel is for tests only.
// The actual Elixir_Kernel is transpiled automatically during project build.
function buildElixirKernelModule() {
  return {
    inspect: buildElixirKernelInspectFunction(),
  };
}

const Elixir_Kernel = buildElixirKernelModule();

export {assert} from "chai";
export const sinon = sinonESM;

export function assertBoxedFalse(boxed) {
  assert.isTrue(Type.isFalse(boxed));
}

export function assertBoxedTrue(boxed) {
  assert.isTrue(Type.isTrue(boxed));
}

export function assertError(callable, errorAliasStr, message) {
  const expectedErrorData = Hologram.serialize(
    Type.errorStruct(errorAliasStr, message)
  );

  assert.throw(callable, Error, `__hologram__:${expectedErrorData}`);
}

export function linkModules() {
  globalThis.Hologram = Hologram;
  globalThis.Erlang = Erlang;
  globalThis.Erlang_maps = Erlang_maps;
  globalThis.Elixir_Enum = {};
  globalThis.Elixir_Kernel = Elixir_Kernel;

  globalThis.Erlang.$243 = $243;
  globalThis.Erlang.$245 = $245;
  globalThis.Erlang.$261$261 = $261$261;
}

export function unlinkModules() {
  delete globalThis.Hologram;
  delete globalThis.Erlang;
  delete globalThis.Erlang_maps;
  delete globalThis.Elixir_Enum;
  delete globalThis.Elixir_Kernel;
}
