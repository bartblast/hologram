"use strict";

import {assert} from "../../../assets/node_modules/chai/index.js";

import ComponentRegistry from "../../../assets/js/component_registry.mjs";
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
import JsonEncoder from "../../../assets/js/json_encoder.mjs";
import Type from "../../../assets/js/type.mjs";

export {assert} from "../../../assets/node_modules/chai/index.js";
import {JSDOM} from "../../../assets/node_modules/jsdom/lib/api.js";
export * as sinon from "../../../assets/node_modules/sinon/pkg/sinon-esm.js";
export {h as vnode} from "../../../assets/node_modules/snabbdom/build/index.js";

export const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

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

export function commandQueueItemFixture(data = {}) {
  let {id, failCount, module, name, params, status, target} = data;

  if (typeof id === "undefined") {
    id = crypto.randomUUID();
  }

  if (typeof failCount === "undefined") {
    failCount = 0;
  }

  if (typeof name === "undefined") {
    name = "my_command";
  }

  if (typeof module === "undefined") {
    module = Type.alias("MyModule");
  }

  if (typeof params === "undefined") {
    params = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);
  }

  if (typeof status === "undefined") {
    status = "pending";
  }

  if (typeof target === "undefined") {
    target = "my_target";
  }

  return {id, failCount, module, name, params, status, target};
}

export function componentRegistryEntryFixture(data = {}) {
  let {module} = data;

  if (typeof module === "undefined") {
    module = Type.alias("MyModule");
  }

  return Type.map([
    [Type.atom("module"), module],
    [Type.atom("struct"), Type.componentStruct(data)],
  ]);
}

export function contextFixture(data = {}) {
  let {module, vars} = data;

  if (typeof module === "undefined") {
    module = "MyModule";
  }

  if (typeof vars === "undefined") {
    vars = {};
  }

  return Interpreter.buildContext({module: module, vars: vars});
}

function defineElixirEnumModule() {
  return {
    "reverse/1": (term) => {
      if (!Type.isList(term) && !Type.isTuple(term)) {
        throw new HologramInterpreterError(
          `not a list or tuple: ${inspectEx(term)}`,
        );
      }

      return {...term, data: term.data.reverse()};
    },
  };
}

function defineElixirHologramRuntimeSettingsModule() {
  return {
    "navigate_to_prefetched_page_action_name/0": () =>
      Type.atom("__navigate_to_prefetched_page__"),

    "prefetch_page_action_name/0": () => Type.atom("__prefetch_page__"),
  };
}

export function defineGlobalErlangAndElixirModules() {
  globalThis.Erlang = Erlang;
  globalThis.Erlang_Code = Erlang_Code;
  globalThis.Erlang_Lists = Erlang_Lists;
  globalThis.Erlang_Maps = Erlang_Maps;
  globalThis.Erlang_Persistent_Term = Erlang_Persistent_Term;
  globalThis.Erlang_Unicode = Erlang_Unicode;
  globalThis.Elixir_Code = Elixir_Code;
  globalThis.Elixir_Enum = defineElixirEnumModule();
  globalThis.Elixir_Hologram_RuntimeSettings =
    defineElixirHologramRuntimeSettingsModule();
  globalThis.Elixir_Kernel = Elixir_Kernel;

  globalThis.Elixir_String_Chars = {};
  globalThis.Elixir_String_Chars["to_string/1"] = elixirStringCharsToString1;
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

export function initComponentRegistryEntry(cid) {
  const entry = componentRegistryEntryFixture();
  ComponentRegistry.putEntry(cid, entry);
}

export function inspectEx(term) {
  console.log(Interpreter.inspect(term));

  return term;
}

export function inspectJs(term) {
  console.log(JsonEncoder.encode(term));

  return term;
}

export function putAction(component, action) {
  return Erlang_Maps["put/3"](Type.atom("next_action"), action, component);
}

export function putCommand(component, command) {
  return Erlang_Maps["put/3"](Type.atom("next_command"), command, component);
}

export function putContext(component, context) {
  const oldContext = Erlang_Maps["get/2"](
    Type.atom("emitted_context"),
    component,
  );

  const newContext = Erlang_Maps["merge/2"](oldContext, context);

  return Erlang_Maps["put/3"](
    Type.atom("emitted_context"),
    newContext,
    component,
  );
}

export function putState(component, state) {
  const oldState = Erlang_Maps["get/2"](Type.atom("state"), component);
  const newState = Erlang_Maps["merge/2"](oldState, state);

  return Erlang_Maps["put/3"](Type.atom("state"), newState, component);
}

export function registerWebApis() {
  const {window} = new JSDOM("", {url: "http://localhost"});

  globalThis.DOMParser = window.DOMParser;
  globalThis.history = window.history;
  globalThis.sessionStorage = window.sessionStorage;
}
