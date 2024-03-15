"use strict";

import {assert} from "../../../assets/node_modules/chai/index.js";

import Elixir_Code from "../../../assets/js/elixir/code.mjs";
import Elixir_Kernel from "../../../assets/js/elixir/kernel.mjs";
import Erlang from "../../../assets/js/erlang/erlang.mjs";
import Erlang_Code from "../../../assets/js/erlang/code.mjs";
import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Erlang_Maps from "../../../assets/js/erlang/maps.mjs";
import Erlang_Persistent_Term from "../../../assets/js/erlang/persistent_term.mjs";
import Erlang_Unicode from "../../../assets/js/erlang/unicode.mjs";
import HologramBoxedError from "../../../assets/js/errors/boxed_error.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
import HologramMatchError from "../../../assets/js/errors/match_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Store from "../../../assets/js/store.mjs";
import Type from "../../../assets/js/type.mjs";

export {assert} from "../../../assets/node_modules/chai/index.js";
export * as sinon from "../../../assets/node_modules/sinon/pkg/sinon-esm.js";
export {h as vnode} from "../../../assets/node_modules/snabbdom/build/index.js";

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

      const receivedErrorType = Interpreter.getErrorType(error);
      const receivedErrorMessage = Interpreter.getErrorMessage(error);
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

export function buildComponentStruct(data) {
  let componentStruct = elixirHologramComponentStruct0();

  const {emittedContext, nextCommand, state} = data;

  if (typeof emittedContext !== "undefined") {
    componentStruct = Erlang_Maps["put/3"](
      Type.atom("emitted_context"),
      emittedContext,
      componentStruct,
    );
  }

  if (typeof nextCommand !== "undefined") {
    componentStruct = Erlang_Maps["put/3"](
      Type.atom("next_command"),
      nextCommand,
      componentStruct,
    );
  }

  if (typeof state !== "undefined") {
    componentStruct = Erlang_Maps["put/3"](
      Type.atom("state"),
      state,
      componentStruct,
    );
  }

  return componentStruct;
}

export function buildContext(data = {}) {
  const {module, vars} = data;
  const context = buildContext();

  if (typeof module !== "undefined") {
    context.module = module;
  }

  if (typeof vars !== "undefined") {
    context.vars = vars;
  }

  return context;
}

export function elixirHologramComponentStruct0() {
  return Type.map([
    [Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component")],
    [Type.atom("emitted_context"), Type.map([])],
    [Type.atom("next_command"), Type.atom("nil")],
    [Type.atom("state"), Type.map([])],
  ]);
}

function elixirStringCharsToString1(term) {
  switch (term.type) {
    case "atom":
      return Type.bitstring(term.value);

    case "bitstring":
      return term;

    case "integer":
      return Type.bitstring(term.value.toString());

    default: {
      const inspectedTerm = Interpreter.inspect(term);
      const msg = `elixirStringCharsToString1() doesn't know how to handle: ${inspectedTerm} of type "${term.type}"`;
      throw new HologramInterpreterError(msg);
    }
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

export function initStoreComponentStruct(cid) {
  const emptyComponentStruct =
    globalThis.Elixir_Hologram_Component["__struct__/0"]();

  Store.putComponentStruct(cid, emptyComponentStruct);
}

export function linkModules() {
  globalThis.Erlang = Erlang;
  globalThis.Erlang_Code = Erlang_Code;
  globalThis.Erlang_Lists = Erlang_Lists;
  globalThis.Erlang_Maps = Erlang_Maps;
  globalThis.Erlang_Persistent_Term = Erlang_Persistent_Term;
  globalThis.Erlang_Unicode = Erlang_Unicode;
  globalThis.Elixir_Code = Elixir_Code;
  globalThis.Elixir_Enum = {};
  globalThis.Elixir_Kernel = Elixir_Kernel;

  globalThis.Elixir_Hologram_Component = {};
  globalThis.Elixir_Hologram_Component["__struct__/0"] =
    elixirHologramComponentStruct0;

  globalThis.Elixir_String_Chars = {};
  globalThis.Elixir_String_Chars["to_string/1"] = elixirStringCharsToString1;
}

export function putComponentState(component, state) {
  const oldState = Erlang_Maps["get/2"](Type.atom("state"), component);
  const newState = Erlang_Maps["merge/2"](oldState, state);

  return Erlang_Maps["put/3"](Type.atom("state"), newState, component);
}

export function unlinkModules() {
  delete globalThis.Erlang;
  delete globalThis.Erlang_Code;
  delete globalThis.Erlang_Lists;
  delete globalThis.Erlang_Maps;
  delete globalThis.Erlang_Persistent_Term;
  delete globalThis.Erlang_Unicode;
  delete globalThis.Elixir_Code;
  delete globalThis.Elixir_Enum;
  delete globalThis.Elixir_Hologram_Component;
  delete globalThis.Elixir_Kernel;
  delete globalThis.Elixir_String_Chars;
}
