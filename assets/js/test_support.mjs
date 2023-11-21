"use strict";

import {assert} from "chai";
import Elixir_Kernel from "./elixir/kernel.mjs";
import Erlang from "./erlang/erlang.mjs";
import Erlang_Lists from "./erlang/lists.mjs";
import Erlang_Maps from "./erlang/maps.mjs";
import Erlang_Persistent_Term from "./erlang/persistent_term.mjs";
import Erlang_Unicode from "./erlang/unicode.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramMatchError from "./errors/match_error.mjs";
import Interpreter from "./interpreter.mjs";
import sinonESM from "../node_modules/sinon/pkg/sinon-esm.js";
import Type from "./type.mjs";

export {assert} from "chai";
export const sinon = sinonESM;

export function assertBoxedError(
  callable,
  expectedErrorType,
  expectedErrorMessage,
) {
  let isErrorThrown = false;
  let isAnyAssertFailed = false;
  let failMessage = `\nexpected:\n${expectedErrorType}: ${expectedErrorMessage}\n`;

  try {
    callable();
  } catch (error) {
    isErrorThrown = true;

    const errorStruct = Type.errorStruct(
      expectedErrorType,
      expectedErrorMessage,
    );

    if (!(error instanceof HologramBoxedError)) {
      isAnyAssertFailed = true;
      failMessage += `but got:\n${error.name}: ${error.message}`;
    } else if (!Interpreter.isStrictlyEqual(error.struct, errorStruct)) {
      isAnyAssertFailed = true;

      const receivedErrorType = Interpreter.fetchErrorType(error);
      const receivedErrorMessage = Interpreter.fetchErrorMessage(error);
      failMessage += `but got:\n${receivedErrorType}: ${receivedErrorMessage}`;
    }
  }

  if (isErrorThrown) {
    if (isAnyAssertFailed) {
      assert.fail(failMessage);
    }
  } else {
    assert.fail(failMessage + "but got no error");
  }
}

export function assertBoxedFalse(boxed) {
  assert.isTrue(Type.isFalse(boxed));
}

export function assertBoxedTrue(boxed) {
  assert.isTrue(Type.isTrue(boxed));
}

export function assertMatchError(callable, value) {
  let isErrorThrown = false;
  let isAnyAssertFailed = false;

  try {
    callable();
  } catch (error) {
    isErrorThrown = true;

    if (!(error instanceof HologramMatchError)) {
      isAnyAssertFailed = true;
    } else if (!Interpreter.isStrictlyEqual(error.value, value)) {
      isAnyAssertFailed = true;
    }
  }

  if (!isErrorThrown || isAnyAssertFailed) {
    assert.fail(
      `expected HologramMatchError with value: ${Interpreter.inspect(value)}`,
    );
  }
}

// Based on deepFreeze() from: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/freeze
export function freeze(obj) {
  const props = Object.getOwnPropertyNames(obj);

  for (const prop of props) {
    const val = obj[prop];

    if (val && typeof val === "object") {
      freeze(val);
    }
  }

  return Object.freeze(obj);
}

export function linkModules() {
  globalThis.Erlang = Erlang;
  globalThis.Erlang_Lists = Erlang_Lists;
  globalThis.Erlang_Maps = Erlang_Maps;
  globalThis.Erlang_Persistent_Term = Erlang_Persistent_Term;
  globalThis.Erlang_Unicode = Erlang_Unicode;
  globalThis.Elixir_Enum = {};
  globalThis.Elixir_Kernel = Elixir_Kernel;
}

export function unlinkModules() {
  delete globalThis.Erlang;
  delete globalThis.Erlang_Lists;
  delete globalThis.Erlang_Maps;
  delete globalThis.Erlang_Persistent_Term;
  delete globalThis.Erlang_Unicode;
  delete globalThis.Elixir_Enum;
  delete globalThis.Elixir_Kernel;
}
