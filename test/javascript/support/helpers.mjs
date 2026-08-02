"use strict";

import {assert} from "../../../assets/node_modules/chai/index.js";

import Bitstring from "../../../assets/js/bitstring.mjs";
import ComponentRegistry from "../../../assets/js/component_registry.mjs";
import Elixir_Code from "../../../assets/js/elixir/code.mjs";
import Elixir_Exception from "../../../assets/js/elixir/exception.mjs";
import Elixir_FunctionClauseError from "../../../assets/js/elixir/function_clause_error.mjs";
import Elixir_Kernel from "../../../assets/js/elixir/kernel.mjs";
import Erlang from "../../../assets/js/erlang/erlang.mjs";
import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Erlang_Code from "../../../assets/js/erlang/code.mjs";
import Erlang_Elixir_Aliases from "../../../assets/js/erlang/elixir_aliases.mjs";
import Erlang_Elixir_Locals from "../../../assets/js/erlang/elixir_locals.mjs";
import Erlang_Erl_Erts_Errors from "../../../assets/js/erlang/erl_erts_errors.mjs";
import Erlang_Erl_Kernel_Errors from "../../../assets/js/erlang/erl_kernel_errors.mjs";
import Erlang_Erl_Stdlib_Errors from "../../../assets/js/erlang/erl_stdlib_errors.mjs";
import Erlang_Filelib from "../../../assets/js/erlang/filelib.mjs";
import Erlang_Filename from "../../../assets/js/erlang/filename.mjs";
import Erlang_Init from "../../../assets/js/erlang/init.mjs";
import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Erlang_Maps from "../../../assets/js/erlang/maps.mjs";
import Erlang_Math from "../../../assets/js/erlang/math.mjs";
import Erlang_Os from "../../../assets/js/erlang/os.mjs";
import Erlang_Persistent_Term from "../../../assets/js/erlang/persistent_term.mjs";
import Erlang_Rand from "../../../assets/js/erlang/rand.mjs";
import Erlang_Re from "../../../assets/js/erlang/re.mjs";
import Erlang_Sets from "../../../assets/js/erlang/sets.mjs";
import Erlang_Unicode from "../../../assets/js/erlang/unicode.mjs";
import Erlang_Uri_String from "../../../assets/js/erlang/uri_string.mjs";
import HologramBoxedError from "../../../assets/js/errors/boxed_error.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import RegexParseError from "../../../assets/js/erts/regex/regex_parse_error.mjs";
import RegexParser from "../../../assets/js/erts/regex/regex_parser.mjs";
import Renderer from "../../../assets/js/renderer.mjs";
import Serializer from "../../../assets/js/serializer.mjs";
import Type from "../../../assets/js/type.mjs";
import Utils from "../../../assets/js/utils.mjs";

export {assert} from "../../../assets/node_modules/chai/index.js";

import {JSDOM} from "../../../assets/node_modules/jsdom/lib/api.js";
export {JSDOM};

export * as sinon from "../../../assets/node_modules/sinon/pkg/sinon-esm.js";
export {h as vnode} from "../../../assets/node_modules/snabbdom/build/index.js";

export const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

// What a boxed error names itself: the exception module and what it says about
// itself. Its message carries the whole report a browser prints for an error
// nobody caught, so the two parts are put back together here.
export function boxedErrorMessage(error) {
  return `(${error.type}) ${error.text}`;
}

export function assertBoxedError(
  callable,
  expectedErrorType,
  expectedErrorMessage,
) {
  let error;

  try {
    callable();
  } catch (e) {
    error = e;
  }

  assertCapturedBoxedError(error, expectedErrorType, expectedErrorMessage);
}

export async function assertBoxedErrorAsync(
  asyncCallable,
  expectedErrorType,
  expectedErrorMessage,
) {
  let error;

  try {
    await asyncCallable();
  } catch (e) {
    error = e;
  }

  assertCapturedBoxedError(error, expectedErrorType, expectedErrorMessage);
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

function assertCapturedBoxedError(
  error,
  expectedErrorType,
  expectedErrorMessage,
) {
  const isRegex = expectedErrorMessage instanceof RegExp;

  const expectedMessageDisplay = isRegex
    ? expectedErrorMessage.toString()
    : expectedErrorMessage;

  const failMessagePrefix = `\nexpected:\n${expectedErrorType}: ${expectedMessageDisplay}\n`;

  if (!error) {
    assert.fail(failMessagePrefix + "but got no error");
  }

  if (!(error instanceof HologramBoxedError)) {
    assert.fail(
      failMessagePrefix + `but got:\n${error.name}: ${error.message}`,
    );
  }

  const receivedErrorType = Interpreter.getErrorType(error);

  // The blamed struct is compared, matching the Elixir consistency helper,
  // which resolves the expected message through Exception.blame/3 as well.
  const receivedErrorMessage = Interpreter.resolveErrorMessage(
    error.blamedStruct,
  );

  const typeMatches = receivedErrorType === expectedErrorType;

  // The derived message text is compared, not the struct shape - errors
  // raised as field-bearing structs and errors raised with an eager :message
  // both pass when they produce the expected text.
  const messageMatches = isRegex
    ? expectedErrorMessage.test(receivedErrorMessage)
    : receivedErrorMessage === expectedErrorMessage;

  if (!typeMatches || !messageMatches) {
    assert.fail(
      failMessagePrefix +
        `but got:\n${receivedErrorType}: ${receivedErrorMessage}`,
    );
  }
}

export function assertRegexParseError(source, message, position, opts = {}) {
  let error = null;

  try {
    RegexParser.parse(source, opts);
  } catch (thrownError) {
    error = thrownError;
  }

  assert.instanceOf(error, RegexParseError);
  assert.equal(error.message, message);
  assert.equal(error.position, position);
}

export function buildArgumentErrorMsg(argumentIndex, message) {
  return buildMultiArgumentErrorMsg([[argumentIndex, message]]);
}

// Keep this message in sync with build_bad_arity_error_msg in Hologram.Commons.TestUtils.
export function buildBadArityErrorMsg(fun, args) {
  let count = "no arguments";

  if (args.length > 0) {
    const inspectedArgs = args
      .map((arg) => Interpreter.inspect(arg))
      .join(", ");
    const noun = args.length === 1 ? "argument" : "arguments";

    count = `${args.length} ${noun} (${inspectedArgs})`;
  }

  return `${Interpreter.inspect(fun)} with arity ${fun.arity} called with ${count}`;
}

// Keep this message in sync with build_bad_function_error_msg in Hologram.Commons.TestUtils.
export function buildBadFunctionErrorMsg(term) {
  return "expected a function, got: " + Interpreter.inspect(term);
}

// Keep this message in sync with build_bad_map_error_msg in Hologram.Commons.TestUtils.
export function buildBadMapErrorMsg(arg) {
  return "expected a map, got:\n\n    " + Interpreter.inspect(arg) + "\n";
}

// Keep this message in sync with build_case_clause_error_msg in Hologram.Commons.TestUtils.
export function buildCaseClauseErrorMsg(arg) {
  return "no case clause matching:\n\n    " + Interpreter.inspect(arg) + "\n";
}

// Keep this message in sync with build_erlang_error_msg in Hologram.Commons.TestUtils.
export function buildErlangErrorMsg(message) {
  return `Erlang error: ${message}`;
}

// Builds the message a clause mismatch produces when no attempted clauses are
// reported, which is what a unit test sees - the clause heads are registered by
// the runtime script, which unit tests don't run.
// Keep this message in sync with build_function_clause_error_msg in Hologram.Commons.TestUtils.
export function buildFunctionClauseErrorMsg(funName, args = null) {
  let argsInfo = "";

  if (args && args.length > 0) {
    argsInfo = Array.from(args).reduce(
      (acc, arg, idx) =>
        `${acc}\n    # ${idx + 1}\n    ${Interpreter.inspect(arg)}\n`,
      `\n\nThe following arguments were given to ${funName}:\n`,
    );
  }

  return `no function clause matching in ${funName}${argsInfo}`;
}

// Keep this message in sync with build_key_error_msg in Hologram.Commons.TestUtils.
export function buildKeyErrorMsg(key, map) {
  const opts = Type.keywordList([
    [
      Type.atom("custom_options"),
      Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
    ],
  ]);

  return `key ${Interpreter.inspect(key)} not found in:\n\n    ${Interpreter.inspect(map, opts)}\n`;
}

// Keep this message in sync with build_match_error_msg in Hologram.Commons.TestUtils.
export function buildMatchErrorMsg(right) {
  return (
    "no match of right hand side value:\n\n    " +
    Interpreter.inspect(right) +
    "\n"
  );
}

// Builds the message for errors at multiple arguments from [index, message]
// entries. Entries with a nullish message are skipped.
// Keep this message in sync with build_multi_argument_error_msg in Hologram.Commons.TestUtils.
export function buildMultiArgumentErrorMsg(entries) {
  const bullets = entries
    .filter(([_index, message]) => message != null)
    .map(
      ([index, message]) =>
        `  * ${Utils.ordinal(index)} argument: ${message}\n`,
    )
    .join("");

  return `errors were found at the given arguments:\n\n${bullets}`;
}

// Keep this message in sync with build_try_clause_error_msg in Hologram.Commons.TestUtils.
export function buildTryClauseErrorMsg(arg) {
  return "no try clause matching:\n\n    " + Interpreter.inspect(arg) + "\n";
}

// Keep this message in sync with build_undefined_function_error_msg in Hologram.Commons.TestUtils.
export function buildUndefinedFunctionErrorMsg(
  module,
  functionName,
  arity,
  isModuleAvailable = true,
) {
  const moduleName = Interpreter.inspect(module);

  if (isModuleAvailable) {
    return `function ${moduleName}.${functionName}/${arity} is undefined or private`;
  }

  return `function ${moduleName}.${functionName}/${arity} is undefined (module ${moduleName} is not available). Make sure the module name is correct and has been specified in full (or that an alias has been defined)`;
}

// Keep this message in sync with build_with_clause_error_msg in Hologram.Commons.TestUtils.
export function buildWithClauseErrorMsg(arg) {
  return "no with clause matching:\n\n    " + Interpreter.inspect(arg) + "\n";
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
  let {module, stacktrace, vars} = data;

  if (typeof module === "undefined") {
    module = "MyModule";
  }

  if (typeof vars === "undefined") {
    vars = {};
  }

  return Interpreter.buildContext({
    module: module,
    stacktrace: stacktrace,
    vars: vars,
  });
}

function defineElixirArithmeticErrorModule() {
  const unaryOps = ["+", "-"];
  const binaryOps = ["*", "+", "-", "/"];
  const binaryFuns = ["div", "rem"];
  const bitwiseBinaryFuns = ["band", "bor", "bsl", "bsr", "bxor"];

  // Mirrors ArithmeticError.blame/2: an :erlang frame with the failed call's
  // args at the top of the stacktrace renders the operation into the message.
  const buildOperationText = (functionName, args) => {
    const inspected = args.map((arg) => Interpreter.inspect(arg));

    if (args.length === 1 && unaryOps.includes(functionName)) {
      return `: ${functionName}(${inspected[0]})`;
    }

    if (args.length === 2 && binaryOps.includes(functionName)) {
      return `: ${inspected[0]} ${functionName} ${inspected[1]}`;
    }

    if (args.length === 2 && binaryFuns.includes(functionName)) {
      return `: ${functionName}(${inspected[0]}, ${inspected[1]})`;
    }

    if (args.length === 2 && bitwiseBinaryFuns.includes(functionName)) {
      return `: Bitwise.${functionName}(${inspected[0]}, ${inspected[1]})`;
    }

    if (args.length === 1 && functionName === "bnot") {
      return `: Bitwise.bnot(${inspected[0]})`;
    }

    return "";
  };

  return {
    "blame/2": (struct, stacktrace) => {
      const topFrame = Type.isList(stacktrace) ? stacktrace.data[0] : undefined;

      let operationText = "";

      if (
        topFrame !== undefined &&
        Type.isAtom(topFrame.data[0]) &&
        topFrame.data[0].value === "erlang" &&
        Type.isList(topFrame.data[2])
      ) {
        operationText = buildOperationText(
          topFrame.data[1].value,
          topFrame.data[2].data,
        );
      }

      const message =
        Bitstring.toText(struct.data["atom(message)"][1]) + operationText;

      return Type.tuple([
        Type.errorStruct("ArithmeticError", message),
        stacktrace,
      ]);
    },
  };
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

function defineElixirExceptionModule() {
  const moduleObj = {
    // Mirrors Exception.blame(:error, reason, stacktrace): the reason is
    // normalized and the exception module's blame/2 callback refines the
    // result when the module defines one.
    "blame/3": (kind, reason, stacktrace) => {
      const struct = moduleObj["normalize/3"](kind, reason, stacktrace);
      const structModule = struct.data["atom(__struct__)"][1];
      const moduleProxy = Interpreter.moduleProxy(structModule);

      if (moduleProxy && "blame/2" in moduleProxy) {
        return moduleProxy["blame/2"](struct, stacktrace);
      }

      return Type.tuple([struct, stacktrace]);
    },

    // Mirrors Exception.format_mfa/3, which spells a call the way source
    // would.
    "format_mfa/3": (module, fun, arity) =>
      Type.bitstring(formatMfa(module, fun.value, arity.value)),

    // Mirrors Exception.format_stacktrace/1: one indented entry per frame,
    // each naming where the call was made and then the call itself.
    "format_stacktrace/1": (stacktrace) =>
      Type.bitstring(
        stacktrace.data
          .map((entry) => `    ${formatStacktraceEntry(entry)}\n`)
          .join(""),
      ),

    // Mirrors Exception.message/1, which delegates to the exception module's
    // message/1 callback. When a test defines the exception module as a
    // global, it is dispatched to. Otherwise the default defexception
    // callback (return the :message field) is mirrored directly, with the
    // inspected struct as a fallback for exceptions without a message field
    // whose modules are not defined.
    "message/1": (struct) => {
      const structModule = struct.data["atom(__struct__)"][1];
      const moduleProxy = Interpreter.moduleProxy(structModule);

      if (moduleProxy && "message/1" in moduleProxy) {
        return moduleProxy["message/1"](struct);
      }

      const messageEntry = struct.data["atom(message)"];

      if (messageEntry !== undefined) {
        return messageEntry[1];
      }

      return Type.bitstring(Interpreter.inspect(struct));
    },

    // Mirrors Exception.normalize(:error, reason, stacktrace): an exception
    // struct passes through unchanged, bare reasons become their exception
    // structs via the ErlangError.normalize clauses (only the ones exercised
    // by tests are mirrored), and any other bare reason is wrapped in an
    // ErlangError struct.
    "normalize/3": (_kind, reason, stacktrace) => {
      if (Type.isStruct(reason)) {
        return reason;
      }

      if (Type.isAtom(reason) && reason.value === "badarg") {
        const applyMessage = deriveApplyErrorMessage(stacktrace);

        if (applyMessage !== null) {
          return Type.errorStruct("ArgumentError", applyMessage);
        }

        const message = deriveErrorInfoMessage(reason, stacktrace);

        return Type.errorStruct("ArgumentError", message ?? "argument error");
      }

      if (Type.isAtom(reason) && reason.value === "badarith") {
        return Type.errorStruct(
          "ArithmeticError",
          "bad argument in arithmetic expression",
        );
      }

      const isTaggedTuple = (tag) =>
        Type.isTuple(reason) &&
        reason.data.length === 2 &&
        Type.isAtom(reason.data[0]) &&
        reason.data[0].value === tag;

      if (isTaggedTuple("badarg")) {
        return Type.errorStruct(
          "ArgumentError",
          `argument error: ${Interpreter.inspect(reason.data[1])}`,
        );
      }

      if (isTaggedTuple("badmap")) {
        return Type.struct("BadMapError", [
          [Type.atom("__exception__"), Type.boolean(true)],
          [Type.atom("term"), reason.data[1]],
        ]);
      }

      if (isTaggedTuple("badkey")) {
        // Mirrors the term recovery from the known stacktrace frame shapes -
        // only the :maps and :erlang.map_get ones are mirrored.
        let term = Type.nil();

        if (Type.isList(stacktrace) && stacktrace.data.length > 0) {
          const topFrame = stacktrace.data[0];

          if (
            Type.isTuple(topFrame) &&
            topFrame.data.length === 4 &&
            Type.isAtom(topFrame.data[0]) &&
            Type.isList(topFrame.data[2])
          ) {
            const moduleName = topFrame.data[0].value;
            const funName = topFrame.data[1].value;
            const args = topFrame.data[2].data;

            if (
              moduleName === "maps" &&
              funName === "get" &&
              args.length === 2
            ) {
              term = args[1];
            } else if (
              moduleName === "maps" &&
              funName === "update" &&
              args.length === 3
            ) {
              term = args[2];
            } else if (
              moduleName === "erlang" &&
              funName === "map_get" &&
              args.length === 2
            ) {
              term = args[1];
            }
          }
        }

        return Type.struct("KeyError", [
          [Type.atom("__exception__"), Type.boolean(true)],
          [Type.atom("key"), reason.data[1]],
          [Type.atom("message"), Type.nil()],
          [Type.atom("term"), term],
        ]);
      }

      return Type.struct("ErlangError", [
        [Type.atom("__exception__"), Type.boolean(true)],
        [Type.atom("original"), reason],
        [Type.atom("reason"), Type.nil()],
      ]);
    },
  };

  return moduleObj;
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

// Returns a stub of a term-bearing exception module (CaseClauseError,
// BadMapError, ...) whose message/1 mirrors the server's derivation: the
// label followed by the inspected term field padded onto its own indented
// line.
function defineElixirTermErrorModule(messageLabel) {
  return {
    "message/1": (struct) => {
      const term = struct.data["atom(term)"][1];

      return Type.bitstring(
        `${messageLabel}\n\n    ${Interpreter.inspect(term)}\n`,
      );
    },
  };
}

function defineGlobalModule(moduleJsName, moduleObj) {
  globalThis[moduleJsName] = moduleObj;
  moduleObj.__exports__ = new Set(Object.keys(moduleObj));
}

export function defineRuntimeGlobals() {
  globalThis.Hologram ??= {};

  // In the browser the runtime bundle bootstrap sets the config object before
  // any dispatch can run - mirror that invariant here. Frame tracking defaults
  // to off, matching how the suite ran before the shadow call stack existed.
  globalThis.Hologram.config ??= {errorOverlay: false, stacktraces: false};

  defineGlobalModule("Erlang", Erlang);
  defineGlobalModule("Erlang_Binary", Erlang_Binary);
  defineGlobalModule("Erlang_Code", Erlang_Code);
  defineGlobalModule("Erlang_Elixir_Aliases", Erlang_Elixir_Aliases);
  defineGlobalModule("Erlang_Elixir_Locals", Erlang_Elixir_Locals);
  defineGlobalModule("Erlang_Erl_Erts_Errors", Erlang_Erl_Erts_Errors);
  defineGlobalModule("Erlang_Erl_Kernel_Errors", Erlang_Erl_Kernel_Errors);
  defineGlobalModule("Erlang_Erl_Stdlib_Errors", Erlang_Erl_Stdlib_Errors);
  defineGlobalModule("Erlang_Filelib", Erlang_Filelib);
  defineGlobalModule("Erlang_Filename", Erlang_Filename);
  defineGlobalModule("Erlang_Init", Erlang_Init);
  defineGlobalModule("Erlang_Lists", Erlang_Lists);
  defineGlobalModule("Erlang_Maps", Erlang_Maps);
  defineGlobalModule("Erlang_Math", Erlang_Math);
  defineGlobalModule("Erlang_Os", Erlang_Os);
  defineGlobalModule("Erlang_Persistent_Term", Erlang_Persistent_Term);
  defineGlobalModule("Erlang_Rand", Erlang_Rand);
  defineGlobalModule("Erlang_Re", Erlang_Re);
  defineGlobalModule("Erlang_Sets", Erlang_Sets);
  defineGlobalModule("Erlang_Unicode", Erlang_Unicode);
  defineGlobalModule("Erlang_Uri_String", Erlang_Uri_String);

  defineGlobalModule(
    "Elixir_ArithmeticError",
    defineElixirArithmeticErrorModule(),
  );

  defineGlobalModule("Elixir_BadArityError", {
    // Mirrors BadArityError.message/1.
    "message/1": (struct) =>
      Type.bitstring(
        buildBadArityErrorMsg(
          struct.data["atom(function)"][1],
          struct.data["atom(args)"][1].data,
        ),
      ),
  });

  defineGlobalModule("Elixir_BadFunctionError", {
    // Mirrors BadFunctionError.message/1 (single-line, unlike the other
    // term-bearing exceptions).
    "message/1": (struct) => {
      const term = struct.data["atom(term)"][1];

      return Type.bitstring(
        `expected a function, got: ${Interpreter.inspect(term)}`,
      );
    },
  });

  defineGlobalModule(
    "Elixir_BadMapError",
    defineElixirTermErrorModule("expected a map, got:"),
  );

  defineGlobalModule(
    "Elixir_CaseClauseError",
    defineElixirTermErrorModule("no case clause matching:"),
  );

  defineGlobalModule("Elixir_Code", Elixir_Code);

  defineGlobalModule("Elixir_CondClauseError", {
    // Mirrors CondClauseError.message/1 (fixed text, no fields).
    "message/1": (_struct) =>
      Type.bitstring("no cond clause evaluated to a truthy value"),
  });

  defineGlobalModule("Elixir_Enum", defineElixirEnumModule());

  defineGlobalModule("Elixir_ErlangError", {
    // Mirrors ErlangError.message/1: an eager message passes through,
    // otherwise the text derives from the inspected original reason.
    "message/1": (struct) => {
      const messageEntry = struct.data["atom(message)"];

      if (messageEntry !== undefined) {
        return messageEntry[1];
      }

      const original = struct.data["atom(original)"][1];

      return Type.bitstring(`Erlang error: ${Interpreter.inspect(original)}`);
    },
  });

  defineGlobalModule("Elixir_Exception", {
    ...defineElixirExceptionModule(),
    // The real port, the way Elixir_FunctionClauseError below is the real one -
    // anything rendering a stacktrace in a test renders it as the client does.
    "format_stacktrace/1": Elixir_Exception["format_stacktrace/1"],
  });

  defineGlobalModule("Elixir_FunctionClauseError", Elixir_FunctionClauseError);

  defineGlobalModule(
    "Elixir_Hologram_Router_Helpers",
    defineElixirHologramRouterHelpersModule(),
  );

  defineGlobalModule("Elixir_Kernel", Elixir_Kernel);

  defineGlobalModule("Elixir_KeyError", {
    // Mirrors KeyError.message/1: an eager message passes through, otherwise
    // the text derives from the key and term fields.
    "message/1": (struct) => {
      const message = struct.data["atom(message)"][1];

      if (!Type.isNil(message)) {
        return message;
      }

      const key = Interpreter.inspect(struct.data["atom(key)"][1]);
      const term = struct.data["atom(term)"][1];

      if (Type.isNil(term)) {
        return Type.bitstring(`key ${key} not found`);
      }

      const opts = Type.keywordList([
        [
          Type.atom("custom_options"),
          Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
        ],
      ]);

      return Type.bitstring(
        `key ${key} not found in:\n\n    ${Interpreter.inspect(term, opts)}\n`,
      );
    },
  });

  defineGlobalModule("Elixir_Macro", {
    // Stands in for Macro.inspect_atom/3, which the client reaches for when an
    // atom's name isn't a plain identifier. It quotes such a name in the
    // position each source format puts it, which is what the transpiled
    // function does for every name except an operator or an alias - those are
    // classified against tables this stand-in doesn't carry, so the Elixir
    // consistency tests are what pin them.
    "inspect_atom/3": (sourceFormat, atom, _opts) => {
      const quoted = `"${atom.value}"`;

      switch (sourceFormat.value) {
        case "key":
          return Type.bitstring(`${quoted}:`);

        case "literal":
          return Type.bitstring(`:${quoted}`);

        default:
          return Type.bitstring(quoted);
      }
    },
  });

  defineGlobalModule(
    "Elixir_MatchError",
    defineElixirTermErrorModule("no match of right hand side value:"),
  );

  defineGlobalModule("Elixir_String_Chars", defineElixirStringCharsModule());

  defineGlobalModule(
    "Elixir_TryClauseError",
    defineElixirTermErrorModule("no try clause matching:"),
  );

  defineGlobalModule("Elixir_UndefinedFunctionError", {
    // Mirrors UndefinedFunctionError.message/1: an eager message passes
    // through, otherwise the text names the missing function and states why
    // the call couldn't be made.
    "message/1": (struct) => {
      const messageEntry = struct.data["atom(message)"];

      if (messageEntry !== undefined && !Type.isNil(messageEntry[1])) {
        return messageEntry[1];
      }

      const module = struct.data["atom(module)"][1];
      const functionName = struct.data["atom(function)"][1].value;
      const arity = struct.data["atom(arity)"][1].value;
      const reason = struct.data["atom(reason)"][1];

      const moduleName = Interpreter.inspect(module);
      const mfa = `${moduleName}.${functionName}/${arity}`;

      if (reason.value !== "module could not be loaded") {
        return Type.bitstring(`function ${mfa} is undefined or private`);
      }

      // The alias hint is offered only for a module named by a single segment,
      // which is what an undefined alias looks like.
      const segments = moduleName.split(".");

      const hint =
        Type.isAlias(module) && segments.length === 1
          ? ". Make sure the module name is correct and has been specified in full (or that an alias has been defined)"
          : "";

      return Type.bitstring(
        `function ${mfa} is undefined (module ${moduleName} is not available)${hint}`,
      );
    },
  });

  defineGlobalModule(
    "Elixir_WithClauseError",
    defineElixirTermErrorModule("no with clause matching:"),
  );
}

// Mirrors the ErlangError.normalize(:badarg, stacktrace) clause that reports
// a non-atom module given to apply/3, picking the hint from what the module
// term turns out to be. Returns null when the raising frame is not such a
// call, leaving the message to the error_info path.
function deriveApplyErrorMessage(stacktrace) {
  if (!Type.isList(stacktrace) || stacktrace.data.length === 0) {
    return null;
  }

  const topFrame = stacktrace.data[0];

  if (!Type.isTuple(topFrame) || topFrame.data.length !== 4) {
    return null;
  }

  const [frameModule, frameFun, frameArgs] = topFrame.data;

  if (
    !Type.isAtom(frameModule) ||
    frameModule.value !== "erlang" ||
    !Type.isAtom(frameFun) ||
    frameFun.value !== "apply" ||
    !Type.isList(frameArgs) ||
    frameArgs.data.length !== 3
  ) {
    return null;
  }

  const [module, functionName, args] = frameArgs.data;

  if (Type.isAtom(module)) {
    return null;
  }

  const applyHint =
    "If you are using Kernel.apply/3, make sure the module is an atom. ";

  const dotSyntaxHint =
    "If you are using the dot syntax, such as module.function(), make sure the left-hand side of the dot is an atom representing a module";

  if (Type.isMap(module) && Type.isAtom(functionName)) {
    const entry = module.data[Type.encodeMapKey(functionName)];

    if (entry !== undefined) {
      const mapHint = Type.isAnonymousFunction(entry[1])
        ? `If you are trying to invoke an anonymous function in a map/struct, add a dot between the function name and the parenthesis: map.${functionName.value}.()`
        : `If you are using the dot syntax, ensure there are no parentheses after the field name, such as map.${functionName.value}`;

      return `you attempted to apply a function named ${Interpreter.inspect(functionName)} on a map/struct. ${applyHint}${mapHint}`;
    }
  }

  if (
    Type.isAtom(functionName) &&
    Type.isList(args) &&
    args.data.length === 0
  ) {
    return `you attempted to apply a function named ${Interpreter.inspect(functionName)} on ${Interpreter.inspect(module)}. ${applyHint}${dotSyntaxHint}`;
  }

  return `you attempted to apply a function on ${Interpreter.inspect(module)}. Modules (the first argument of apply) must always be an atom`;
}

// Mirrors ErlangError.error_info/3: reads error_info from the top stacktrace
// frame, dispatches to the format module's format_error/2 (or to the function
// the error_info names instead), and renders the fragments into the message -
// the positional ones into the multi-argument listing, a general one into the
// reason-prefixed one-liner. Returns null when no message can be derived (no
// error_info, no format module, or no fragments).
function deriveErrorInfoMessage(reason, stacktrace) {
  if (!Type.isList(stacktrace) || stacktrace.data.length === 0) {
    return null;
  }

  const topFrame = stacktrace.data[0];

  if (!Type.isTuple(topFrame) || topFrame.data.length !== 4) {
    return null;
  }

  const [frameModule, _frameFun, argsOrArity, opts] = topFrame.data;

  if (!Type.isList(opts)) {
    return null;
  }

  const errorInfoEntry = opts.data.find(
    (opt) =>
      Type.isTuple(opt) &&
      opt.data.length === 2 &&
      Type.isAtom(opt.data[0]) &&
      opt.data[0].value === "error_info",
  );

  if (errorInfoEntry === undefined || !Type.isMap(errorInfoEntry.data[1])) {
    return null;
  }

  const errorInfoMap = errorInfoEntry.data[1];
  const errorModule = errorInfoMap.data["atom(module)"]?.[1] ?? frameModule;
  const errorModuleProxy = Interpreter.moduleProxy(errorModule);

  const errorFun =
    errorInfoMap.data["atom(function)"]?.[1].value ?? "format_error";
  const errorFunKey = `${errorFun}/2`;

  if (!errorModuleProxy || !(errorFunKey in errorModuleProxy)) {
    return null;
  }

  const fragments = errorModuleProxy[errorFunKey](reason, stacktrace);

  const arity = Type.isInteger(argsOrArity)
    ? Number(argsOrArity.value)
    : argsOrArity.data.length;

  const flattenChardata = (term) =>
    Type.isList(term)
      ? term.data.map(flattenChardata).join("")
      : Bitstring.toText(term);

  const entries = Object.values(fragments.data)
    .filter(
      ([key, _value]) => Type.isInteger(key) && Number(key.value) <= arity,
    )
    .map(([key, value]) => [Number(key.value), flattenChardata(value)])
    .sort(([n1, _msg1], [n2, _msg2]) => n1 - n2);

  if (entries.length > 0) {
    return buildMultiArgumentErrorMsg(entries);
  }

  const general = fragments.data["atom(general)"]?.[1];

  if (general === undefined) {
    return null;
  }

  const reasonFragment = fragments.data["atom(reason)"]?.[1];

  const reasonText = reasonFragment
    ? flattenChardata(reasonFragment)
    : "errors were found at the given arguments";

  return `${reasonText}: ${flattenChardata(general)}`;
}

export function encodedSubscriptionReceiptKey(channel, cid) {
  return Type.encodeMapKey(Type.tuple([channel, Type.bitstring(cid)]));
}

// Mirrors Code.Identifier.extract_anonymous_fun_parent/1: the name the BEAM
// gives a function defined inside another one spells out the definition it
// belongs to.
function extractAnonymousFunParent(functionName) {
  if (!functionName.startsWith("-")) {
    return null;
  }

  const segments = functionName.slice(1).split("/");
  const trailing = segments.pop().split("-");

  if (trailing.length !== 4 || trailing[3] !== "") {
    return null;
  }

  return {name: segments.join("/"), arity: trailing[0]};
}

// Mirrors Exception.format_mfa/3, simplified: the function name is quoted
// unless it reads as a plain identifier, whereas the server also leaves the
// operator names unquoted.
function formatMfa(module, functionName, arity) {
  const parent = extractAnonymousFunParent(functionName);
  const moduleName = Interpreter.inspect(module);

  if (parent !== null) {
    return `anonymous fn/${arity} in ${moduleName}.${parent.name}/${parent.arity}`;
  }

  const inspectedName = /^[_a-zA-Z][_a-zA-Z0-9]*[?!]?$/.test(functionName)
    ? functionName
    : `"${functionName}"`;

  return `${moduleName}.${inspectedName}/${arity}`;
}

// Mirrors Exception.format_stacktrace_entry/1 for the frames the tests build:
// the file and line the call was made from, then the call. A frame carrying
// args spells them out in place of the arity, as the server does.
function formatStacktraceEntry(entry) {
  const [module, fun, arityOrArgs, location] = entry.data;

  const locationValue = (key) =>
    location.data.find((item) => item.data[0].value === key)?.data[1];

  const file = locationValue("file").data.map((byte) =>
    String.fromCharCode(Number(byte.value)),
  );

  const line = locationValue("line").value;

  const call = Type.isList(arityOrArgs)
    ? `${Interpreter.inspect(module)}.${fun.value}(${arityOrArgs.data
        .map((arg) => Interpreter.inspect(arg))
        .join(", ")})`
    : formatMfa(module, fun.value, arityOrArgs.value);

  return `${file.join("")}:${line}: ${call}`;
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

export function initComponentRegistryEntry(cid, module) {
  const entry = componentRegistryEntryFixture({module});
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
  globalThis.document = window.document;
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
