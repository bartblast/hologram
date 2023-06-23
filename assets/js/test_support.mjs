"use strict";

import {assert} from "chai";
import Elixir_Kernel from "./elixir/kernel.mjs";
import Erlang from "./erlang/erlang.mjs";
import Erlang_maps from "./erlang/maps.mjs";
import Hologram from "./hologram.mjs";
import sinonESM from "../node_modules/sinon/pkg/sinon-esm.js";
import Type from "./type.mjs";

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

export function assertFrozen(obj) {
  assert.isTrue(Object.isFrozen(obj));
}

export function assertNotFrozen(obj) {
  assert.isFalse(Object.isFrozen(obj));
}

export function linkModules() {
  globalThis.Hologram = Hologram;
  globalThis.Erlang = Erlang;
  globalThis.Erlang_maps = Erlang_maps;
  globalThis.Elixir_Kernel = Elixir_Kernel;
}

export function unlinkModules() {
  delete globalThis.Hologram;
  delete globalThis.Erlang;
  delete globalThis.Erlang_maps;
  delete globalThis.Elixir_Kernel;
}
