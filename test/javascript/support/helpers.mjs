"use strict";

import {assert} from "../../../assets/node_modules/chai/index.js";

import Bitstring from "../../../assets/js/bitstring.mjs";
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
import Interpreter from "../../../assets/js/interpreter.mjs";
import Renderer from "../../../assets/js/renderer.mjs";
import Serializer from "../../../assets/js/serializer.mjs";
import Type from "../../../assets/js/type.mjs";

export {assert} from "../../../assets/node_modules/chai/index.js";

import {JSDOM} from "../../../assets/node_modules/jsdom/lib/api.js";
export {JSDOM};

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

export function assertBoxedStrictEqual(left, right) {
  if (!Interpreter.isStrictlyEqual(left, right)) {
    const inspectLeft = Interpreter.inspect(left);
    const inspectRight = Interpreter.inspect(right);
    const failMessage = `expected (boxed) ${inspectLeft} to strictly equal (boxed) ${inspectRight}`;

    assert.fail(failMessage);
  }
}

export function assertBoxedTrue(boxed) {
  assert.isTrue(Type.isTrue(boxed));
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

      return {...term, data: term.data.toReversed()};
    },
  };
}

function defineElixirHologramRouterHelpersModule() {
  return {
    "page_path/1": (arg) => {
      const page_path_2 = Elixir_Hologram_Router_Helpers["page_path/2"];

      if (Type.isTuple(arg)) {
        return page_path_2(arg.data[0], arg.data[1]);
      }

      return page_path_2(arg, Type.keywordList());
    },

    // Deps: [String.Chars.to_string/1, :lists.keyfind/3, :lists.keymember/3]
    "page_path/2": (pageModule, params) => {
      const context = Interpreter.buildContext();

      const requiredParams = Interpreter.callNamedFunction(
        pageModule,
        Type.atom("__params__"),
        Type.list(),
        context,
      );

      const route = Interpreter.callNamedFunction(
        pageModule,
        Type.atom("__route__"),
        Type.list(),
        context,
      );

      const [remainingParams, path] = requiredParams.data.reduce(
        (acc, requiredParam) => {
          const key = requiredParam.data[0];
          const paramsAcc = acc[0];
          const pathAcc = acc[1];

          if (
            Type.isFalse(
              Erlang_Lists["keymember/3"](key, Type.integer(1), paramsAcc),
            )
          ) {
            const msg = `page "${Interpreter.inspect(pageModule)}" expects "${key.value}" param`;
            Interpreter.raiseArgumentError(msg);
          }

          const newParamsAcc = Type.list(
            paramsAcc.data.filter((param) => param.data[0].value !== key.value),
          );

          const paramValue = Erlang_Lists["keyfind/3"](
            key,
            Type.integer(1),
            paramsAcc,
          ).data[1];

          const paramValueText = Bitstring.toText(
            Elixir_String_Chars["to_string/1"](paramValue),
          );

          const newPathAcc = Type.bitstring(
            Bitstring.toText(pathAcc).replaceAll(
              `:${key.value}`,
              paramValueText,
            ),
          );

          return [newParamsAcc, newPathAcc];
        },
        [params, route],
      );

      if (remainingParams.data.length > 0) {
        const key = remainingParams.data[0].data[0];

        const msg = `page "${Interpreter.inspect(pageModule)}" doesn't expect "${key.value}" param`;
        Interpreter.raiseArgumentError(msg);
      }

      return path;
    },
  };
}

function defineElixirStringCharsModule() {
  return {
    "to_string/1": (term) => {
      if (Type.isAtom(term) || Type.isBinary(term) || Type.isNumber(term)) {
        return Type.bitstring(Renderer.toText(term));
      }

      return Type.bitstring("Dummy String.Chars protocol result");
    },
  };
}

export function defineGlobalErlangAndElixirModules() {
  globalThis.hologram ??= {};

  globalThis.Erlang = Erlang;
  globalThis.Erlang_Code = Erlang_Code;
  globalThis.Erlang_Lists = Erlang_Lists;
  globalThis.Erlang_Maps = Erlang_Maps;
  globalThis.Erlang_Persistent_Term = Erlang_Persistent_Term;
  globalThis.Erlang_Unicode = Erlang_Unicode;
  globalThis.Elixir_Code = Elixir_Code;
  globalThis.Elixir_Enum = defineElixirEnumModule();

  globalThis.Elixir_Hologram_Router_Helpers =
    defineElixirHologramRouterHelpersModule();

  globalThis.Elixir_Kernel = Elixir_Kernel;
  globalThis.Elixir_String_Chars = defineElixirStringCharsModule();
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
  console.log(Serializer.serialize(term, "client"));
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

export function putPage(component, pageModule) {
  return Erlang_Maps["put/3"](Type.atom("next_page"), pageModule, component);
}

export function putState(component, state) {
  const oldState = Erlang_Maps["get/2"](Type.atom("state"), component);
  const newState = Erlang_Maps["merge/2"](oldState, state);

  return Erlang_Maps["put/3"](Type.atom("state"), newState, component);
}

export function registerWebApis() {
  const {window} = new JSDOM("", {url: "http://localhost"});

  globalThis.window = window;
  globalThis.console = window.console;
  globalThis.DOMParser = window.DOMParser;

  globalThis.fetch =
    window.fetch ||
    (() =>
      Promise.reject(new Error("Fetch not implemented in test environment")));

  globalThis.FormData = window.FormData;
  globalThis.history = window.history;
  globalThis.sessionStorage = window.sessionStorage;
  globalThis.WebSocket = window.WebSocket;
}

// Waits for asynchronous operations scheduled with setTimeout(..., 0) to complete.
// This is useful in tests when you need to wait for async actions that are scheduled
// to run on the next tick of the event loop.
export function waitForEventLoop() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}
