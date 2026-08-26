"use strict";

import Bitstring from "./bitstring.mjs";
import CallStack from "./erts/call_stack.mjs";
import ERTS from "./erts.mjs";
import HologramBoxedError from "./errors/boxed_error.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import NodeTable from "./erts/node_table.mjs";
import PerformanceTimer from "./performance_timer.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

import uniqWith from "lodash/uniqWith.js";

// Sentinel returned by the rescue/catch clause evaluators when no clause matched.
// A unique value (not false/null) so that a clause body returning a falsy Elixir
// term (nil/false) is never mistaken for "no clause matched".
const NO_MATCH = Symbol("NO_MATCH");

// The OTP application a module belongs to decides which formatter its BIF errors name: erts
// modules name erl_erts_errors, kernel modules name erl_kernel_errors, and the rest are stdlib
// modules naming erl_stdlib_errors. Only the modules that depart from the stdlib default are
// listed - a raise site whose module names a different formatter states it at the site.
const BIF_FORMAT_MODULES = {erlang: "erl_erts_errors", os: "erl_kernel_errors"};

// Atoms whose names match render without asking Elixir how to - see #inspectAtomAs().
// ALIAS_REGEX mirrors Macro's valid_alias?/1: "Elixir" followed by dot-separated segments,
// each starting with an uppercase letter.
const ALIAS_REGEX = /^Elixir(\.[A-Z][a-zA-Z0-9_]*)*$/;
const ATOM_IDENTIFIER_REGEX = /^[a-z_][a-zA-Z0-9_]*[?!]?$/;

const ATOM_FAST_PATHS = {
  key: (name) => `${name}:`,
  literal: (name) => `:${name}`,
  remote_call: (name) => name,
};

// The characters printable text shows as an escape sequence instead of itself:
// the control characters that have a letter escape, and the quote and backslash
// that would otherwise close or escape the literal. Anything the regex below
// matches without an entry here is invisible and renders as \uXXXX.
const TEXT_ESCAPES = {
  7: "\\a",
  8: "\\b",
  9: "\\t",
  10: "\\n",
  11: "\\v",
  12: "\\f",
  13: "\\r",
  27: "\\e",
  34: '\\"',
  92: "\\\\",
  127: "\\d",
};

// What printable text doesn't spell as itself: the characters above, the
// invisible codepoints - spaces other than the plain one, joiners, direction
// marks and annotation controls, which String.printable?/2 still accepts - and
// the interpolation opener, matched as a pair since a "#" alone stands for
// itself.
const TEXT_ESCAPE_REGEX =
  // The control characters are matched on purpose, and every codepoint below
  // is written as an escape - so the pair the character class rule reads as one
  // combined character is two that the text really holds.
  // eslint-disable-next-line no-control-regex, no-misleading-character-class
  /#\{|[\x07-\x0D\x1B"\\\x7F\u00A0\u034F\u061C\u2000-\u200F\u2028-\u202E\u205F-\u2064\u2066-\u2069\uFEFF\uFFF9-\uFFFC]/g;

export default class Interpreter {
  // Clause heads of manually ported functions, keyed by "Module.function/arity".
  static #functionClauseHeads = {};

  // Deps: [:lists.keyfind/3]
  static accessKeywordListElement(keywordList, key, defaultValue = null) {
    const keyfindRes = Erlang_Lists["keyfind/3"](
      key,
      Type.integer(1),
      keywordList,
    );

    return Type.isTuple(keyfindRes) ? keyfindRes.data[1] : defaultValue;
  }

  // TODO: Remove when structural comparison is fully implemented.
  // See: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // and :erlang.</2, :erlang.>/2 and similar
  static assertStructuralComparisonSupportedType(term) {
    if (
      !Type.isAtom(term) &&
      !Type.isBitstring(term) &&
      !Type.isFloat(term) &&
      !Type.isInteger(term) &&
      !Type.isList(term) &&
      !Type.isPid(term) &&
      !Type.isTuple(term)
    ) {
      const message = `Structural comparison currently supports only atoms, bitstrings, floats, integers, lists, pids and tuples, got: ${Interpreter.inspect(
        term,
      )}`;

      throw new HologramInterpreterError(message);
    }
  }

  // Turns an :error reason into the exception struct in its display form,
  // mirroring Elixir's Exception.blame/3: the reason is normalized and the
  // exception module's blame/2 callback refines the struct against the
  // stacktrace (e.g. ArithmeticError appending the failed operation). Only
  // the struct is taken from the returned pair - the client keeps reporting
  // the raw trace, the way rescue clauses see it.
  // Deps: [Exception.blame/3]
  static blameError(reason, stacktrace = Type.list()) {
    const result = Elixir_Exception["blame/3"](
      Type.atom("error"),
      reason,
      stacktrace,
    );

    return result.data[0];
  }

  // Boxes the stacktrace carried on an error. A trace given to :erlang.raise/3
  // is stored already boxed, while a captured one is an array of frame objects.
  // The frames an error carries, boxed. An error raised through
  // :erlang.raise/3 already carries them boxed, one raised any other way
  // carries the shadow call stack's own frames.
  static boxStacktrace(error) {
    return Type.isList(error.stacktrace)
      ? error.stacktrace
      : Type.list(error.stacktrace.map(CallStack.boxFrame));
  }

  static buildContext(data = {}) {
    const {module, stacktrace, vars} = data;
    const context = {module: null, stacktrace: null, vars: {}};

    if (module) {
      context.module = Type.isAlias(module) ? module : Type.alias(module);
    }

    if (stacktrace) {
      context.stacktrace = stacktrace;
    }

    if (vars) {
      context.vars = vars;
    }

    return context;
  }

  // Hologram-specific, no server-side equivalent.
  static buildTooBigOutputErrorMsg(mfa) {
    return (
      `${mfa} can't be transpiled automatically to JavaScript, because its output is too big.\n` +
      "See what to do here: https://www.hologram.page/TODO"
    );
  }

  // Apart from the frame tracking unit tests, callAnonymousFunction() has no
  // unit tests in interpreter_test.mjs, only:
  // * feature tests in test/features/test/function_calls/anonymous_function_test.exs,
  // * feature tests in test/features/test/function_calls/function_capture_test.exs,
  // * consistency tests in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call anonymous function section).
  // * consistency tests in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call function capture section).
  // Unit test maintenance in interpreter_test.mjs would be problematic because tests would need to be updated
  // each time Hologram.Compiler.Encoder's implementation changes.
  static callAnonymousFunction(fun, argsArray) {
    if (argsArray.length !== fun.arity) {
      Interpreter.raiseBadArityError(fun, argsArray);
    }

    // A capture of a named function pushes no frame of its own - the call
    // delegates to the named function, whose own dispatch wrapper pushes the
    // frame, matching the BEAM where such a capture IS the named function.
    let popsFrameOnExit =
      globalThis.Hologram.config.stacktraces && fun.capturedModule === null;

    let frame = null;

    if (popsFrameOnExit) {
      const definingModule = fun.context.module
        ? Interpreter.moduleExName(fun.context.module)
        : null;

      frame = {
        module: definingModule,
        function: fun.name,
        arityOrArgs: fun.arity,
        file: ERTS.moduleMetadata[definingModule]?.file ?? null,
        line: null,
        errorInfo: null,
      };

      CallStack.push(frame);
    }

    try {
      const args = Type.list(argsArray);

      for (const clause of fun.clauses) {
        const contextClone = Interpreter.cloneContext(fun.context);
        const pattern = Type.list(clause.params(contextClone));

        if (Interpreter.isMatched(pattern, args, contextClone)) {
          Interpreter.updateVarsToMatchedValues(contextClone);

          if (Interpreter.#evaluateGuards(clause.guards, contextClone)) {
            // The frame is pushed before clause dispatch, so which line it
            // points at is known only now, once a clause has matched.
            if (frame) {
              frame.line = clause.line ?? null;
            }

            const result = clause.body(contextClone);

            // An async body is still executing when it returns its promise,
            // so the frame pops when the promise settles instead of on
            // return - otherwise every frame below an await would be gone by
            // the time an error is raised there.
            if (popsFrameOnExit && result instanceof Promise) {
              popsFrameOnExit = false;
              return result.finally(() => CallStack.pop());
            }

            return result;
          }
        }
      }

      // No clause matched, so the loop above never recorded a line. The BEAM
      // reports the first clause, which is where the function starts.
      if (frame) {
        frame.line = fun.clauses[0]?.line ?? null;
      }

      Interpreter.raiseFunctionClauseError(
        fun.context.module
          ? Interpreter.moduleExName(fun.context.module)
          : null,
        fun.name,
        fun.arity,
        argsArray,
      );
    } finally {
      if (popsFrameOnExit) {
        CallStack.pop();
      }
    }
  }

  // callNamedFunction() has no unit tests in interpreter_test.mjs, only:
  // * feature tests in test/features/test/function_calls/local_function_test.exs,
  // * feature tests in test/features/test/function_calls/remote_function_test.exs,
  // * consistency tests in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call local function section).
  // * consistency tests in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call remote function section).
  // Unit test maintenance in interpreter_test.mjs would be problematic because tests would need to be updated
  // each time Hologram.Compiler.Encoder's implementation changes.
  static callNamedFunction(module, functionName, args, context) {
    const moduleProxy = Interpreter.moduleProxy(module);
    const arity = args.data.length;
    const functionArityStr = `${functionName.value}/${arity}`;

    if (typeof moduleProxy === "undefined") {
      Interpreter.raiseUndefinedFunctionError(
        module,
        functionName.value,
        arity,
        false,
      );
    }

    if (
      moduleProxy.__exports__ &&
      !moduleProxy.__exports__.has(functionArityStr) &&
      !Interpreter.isEqual(module, context.module)
    ) {
      Interpreter.raiseUndefinedFunctionError(
        module,
        functionName.value,
        arity,
      );
    }

    return moduleProxy[functionArityStr](...args.data);
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update asyncCase().
  // case() has no unit tests in interpreter_test.mjs, only feature tests in test/features/test/control_flow/case_test.exs
  // Unit test maintenance in interpreter_test.mjs would be problematic because tests would need to be updated
  // each time Hologram.Compiler.Encoder's implementation changes.
  static case(condition, clauses, context) {
    return Interpreter.#evaluateMatchingClause(
      condition,
      clauses,
      context,
      Interpreter.raiseCaseClauseError,
    );
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update case().
  static async asyncCase(condition, clauses, context) {
    return await Interpreter.#asyncEvaluateMatchingClause(
      condition,
      clauses,
      context,
      Interpreter.raiseCaseClauseError,
    );
  }

  static cloneContext(context) {
    // Use {...obj} instead of Object.assign({}, obj) for shallow copying,
    // see benchmarks here: https://thecodebarbarian.com/object-assign-vs-object-spread.html
    return {
      module: context.module,
      stacktrace: context.stacktrace,
      vars: {...context.vars},
    };
  }

  // Implements structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // TODO: support comparing the remaining types: anonymous function, map, port, reference
  static compareTerms(term1, term2) {
    Interpreter.assertStructuralComparisonSupportedType(term1);
    Interpreter.assertStructuralComparisonSupportedType(term2);

    const term1TypeOrder = Interpreter.getStructuralComparisonTypeOrder(term1);
    const term2TypeOrder = Interpreter.getStructuralComparisonTypeOrder(term2);

    if (term1TypeOrder !== term2TypeOrder) {
      return term1TypeOrder < term2TypeOrder ? -1 : 1;
    }

    switch (term1.type) {
      case "atom":
      case "float":
      case "integer":
        return term1.value == term2.value
          ? 0
          : term1.value < term2.value
            ? -1
            : 1;

      case "bitstring":
        return Bitstring.compare(term1, term2);

      case "list":
        return Interpreter.#compareLists(term1, term2);

      case "pid":
        return Interpreter.#comparePids(term1, term2);

      case "tuple":
        return Interpreter.#compareTuples(term1, term2);
    }
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update asyncComprehension().
  // Deps: [Enum.into/2, Enum.to_list/1]
  static comprehension(qualifiers, collectable, unique, mapper, context) {
    let items = [];

    Interpreter.#walkComprehension(qualifiers, 0, context, (leafContext) =>
      items.push(mapper(leafContext)),
    );

    if (unique) {
      items = uniqWith(items, Interpreter.isStrictlyEqual);
    }

    return Elixir_Enum["into/2"](Type.list(items), collectable);
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update comprehension().
  // Deps: [Enum.into/2, Enum.to_list/1]
  static async asyncComprehension(
    qualifiers,
    collectable,
    unique,
    mapper,
    context,
  ) {
    let items = [];

    await Interpreter.#asyncWalkComprehension(
      qualifiers,
      0,
      context,
      async (leafContext) => items.push(await mapper(leafContext)),
    );

    if (unique) {
      items = uniqWith(items, Interpreter.isStrictlyEqual);
    }

    return Elixir_Enum["into/2"](Type.list(items), collectable);
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update asyncComprehensionReduce().
  // Deps: [Enum.to_list/1]
  static comprehensionReduce(qualifiers, initialValue, clauses, context) {
    let acc = initialValue;

    Interpreter.#walkComprehension(qualifiers, 0, context, (leafContext) => {
      acc = Interpreter.#evaluateMatchingClause(
        acc,
        clauses,
        leafContext,
        Interpreter.raiseCaseClauseError,
      );
    });

    return acc;
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update comprehensionReduce().
  // Deps: [Enum.to_list/1]
  static async asyncComprehensionReduce(
    qualifiers,
    initialValue,
    clauses,
    context,
  ) {
    let acc = initialValue;

    await Interpreter.#asyncWalkComprehension(
      qualifiers,
      0,
      context,
      async (leafContext) => {
        acc = await Interpreter.#asyncEvaluateMatchingClause(
          acc,
          clauses,
          leafContext,
          Interpreter.raiseCaseClauseError,
        );
      },
    );

    return acc;
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update asyncCond().
  // cond() has no unit tests in interpreter_test.mjs, only feature tests in test/features/test/control_flow/cond_test.exs
  // Unit test maintenance in interpreter_test.mjs would be problematic because tests would need to be updated
  // each time Hologram.Compiler.Encoder's implementation changes.
  static cond(clauses, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Type.isTruthy(clause.condition(contextClone))) {
        Interpreter.updateVarsToMatchedValues(contextClone);
        return clause.body(contextClone);
      }
    }

    Interpreter.#raiseCondClauseError();
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update cond().
  static async asyncCond(clauses, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Type.isTruthy(await clause.condition(contextClone))) {
        Interpreter.updateVarsToMatchedValues(contextClone);
        return await clause.body(contextClone);
      }
    }

    Interpreter.#raiseCondClauseError();
  }

  static consOperator(head, tail) {
    if (Type.isProperList(tail)) {
      return Type.list([head].concat(tail.data));
    } else {
      return Type.improperList([head, tail]);
    }
  }

  static defineElixirFunction(
    moduleExName,
    functionName,
    arity,
    visibility,
    clauses,
  ) {
    const moduleJsName = Interpreter.moduleJsName("Elixir." + moduleExName);

    Interpreter.maybeInitModuleProxy(moduleExName, moduleJsName);

    globalThis[moduleJsName][`${functionName}/${arity}`] =
      Interpreter.#buildElixirFunction(
        moduleExName,
        functionName,
        arity,
        visibility,
        clauses,
        ERTS.moduleMetadata[moduleExName]?.file ?? null,
      );

    if (visibility === "public") {
      globalThis[moduleJsName].__exports__.add(`${functionName}/${arity}`);
    }
  }

  static defineErlangFunction(moduleExName, functionName, arity, jsFunction) {
    const moduleJsName = Interpreter.moduleJsName(moduleExName);
    const functionArityStr = `${functionName}/${arity}`;

    Interpreter.maybeInitModuleProxy(moduleExName, moduleJsName, "erlang");

    globalThis[moduleJsName][functionArityStr] =
      Interpreter.#buildFrameTrackingWrapper(
        moduleExName,
        functionName,
        arity,
        null,
        jsFunction,
      );

    globalThis[moduleJsName].__exports__.add(functionArityStr);
  }

  // Registers the clause heads a manually ported function stands in for, so its
  // raise sites can report attempted clauses. Ported functions have no encoded
  // clauses of their own - only the JavaScript implementation - so the heads
  // arrive separately, without bodies.
  static defineFunctionClauseHeads(
    moduleExName,
    functionName,
    arity,
    visibility,
    clauseHeads,
  ) {
    const key = `${moduleExName}.${functionName}/${arity}`;

    Interpreter.#functionClauseHeads[key] = {visibility, clauses: clauseHeads};
  }

  static defineManuallyPortedFunction(
    moduleExName,
    functionArityStr,
    visibility,
    fun,
  ) {
    const moduleJsName = Interpreter.moduleJsName("Elixir." + moduleExName);

    // The arity separator is the last slash - operator function names such as
    // "..//" contain slashes of their own.
    const separatorIndex = functionArityStr.lastIndexOf("/");
    const functionName = functionArityStr.slice(0, separatorIndex);
    const arity = Number(functionArityStr.slice(separatorIndex + 1));

    Interpreter.maybeInitModuleProxy(moduleExName, moduleJsName);

    globalThis[moduleJsName][functionArityStr] =
      Interpreter.#buildFrameTrackingWrapper(
        moduleExName,
        functionName,
        arity,
        null,
        fun,
      );

    if (visibility === "public") {
      globalThis[moduleJsName].__exports__.add(functionArityStr);
    }
  }

  static defineNotImplementedErlangFunction(moduleExName, functionName, arity) {
    const moduleJsName = Interpreter.moduleJsName(moduleExName);

    Interpreter.maybeInitModuleProxy(moduleExName, moduleJsName, "erlang");

    globalThis[moduleJsName][`${functionName}/${arity}`] = () => {
      const message =
        `Function :${moduleExName}.${functionName}/${arity} is not yet ported.\n` +
        `  * Check implementation status: https://hologram.page/reference/client-runtime\n` +
        `  * If the function is not marked 'in progress' and is critical for your project, you may request it here: https://github.com/bartblast/hologram/issues`;

      throw new HologramInterpreterError(message);
    };
  }

  // Deps: [:maps.get/2]
  static dotOperator(left, right) {
    // if left argument is a boxed atom, treat the operator as a remote function call
    if (Type.isAtom(left)) {
      const functionArityStr = `${right.value}/0`;
      return Interpreter.moduleProxy(left)[functionArityStr]();
    }

    // otherwise treat the operator as map key access
    return Erlang_Maps["get/2"](right, left);
  }

  static evaluateJavaScriptCode(code) {
    const context = Interpreter.buildContext();

    // See why not to use eval() with esbuild and in general: https://esbuild.github.io/content-types/#direct-eval
    return new Function("context", "Type", "Interpreter", code)(
      context,
      Type,
      Interpreter,
    );
  }

  static evaluateJavaScriptExpression(expr) {
    return Interpreter.evaluateJavaScriptCode(`return (${expr});`);
  }

  // Renders a boxed error the way the server renders an uncaught one: the
  // banner naming the exception and what it says about itself, then the stacktrace, which
  // the ported Exception.format_stacktrace/1 renders so the frames read as
  // they do on the server. Both trace shapes an error can carry render the
  // same. A frameless error is its banner alone, as Exception.format/3 leaves
  // the section off for an empty stacktrace.
  // Deps: [Exception.format_stacktrace/1]
  static formatBoxedError(error) {
    const banner = `** (${error.type}) ${error.text}`;
    const boxedStacktrace = $.boxStacktrace(error);

    if (boxedStacktrace.data.length === 0) {
      return banner;
    }

    const stacktraceText = Bitstring.toText(
      Elixir_Exception["format_stacktrace/1"](boxedStacktrace),
    );

    return `${banner}\n${stacktraceText}`;
  }

  // Returns the registered clause heads of the given function, or null when it
  // has none.
  static functionClauseHeads(moduleExName, functionName, arity) {
    const key = `${moduleExName}.${functionName}/${arity}`;

    return Interpreter.#functionClauseHeads[key] ?? null;
  }

  // Renders the exception struct's module the way the server renders it in
  // an error banner: inspect(exception.__struct__).
  static getErrorType(jsError) {
    const structModule = jsError.struct.data["atom(__struct__)"][1];

    return Interpreter.inspect(structModule);
  }

  // See type ordering spec: https://hexdocs.pm/elixir/main/Kernel.html#module-term-ordering
  static getStructuralComparisonTypeOrder(term) {
    switch (term.type) {
      case "anonymous_function":
        return 4;

      case "atom":
        return 2;

      case "bitstring":
        return 10;

      case "float":
      case "integer":
        return 1;

      case "list":
        return 9;

      case "map":
        return 8;

      case "pid":
        return 6;

      case "port":
        return 5;

      case "reference":
        return 3;

      case "tuple":
        return 7;
    }
  }

  // TODO: use String.Chars (to_string/1) protocol for structs
  // TODO: implement opts param
  static inspect(term, opts = Type.keywordList()) {
    // Cases ordered by expected frequency (most common first)
    switch (term.type) {
      case "atom":
        return Interpreter.#inspectAtom(term, opts);

      case "map":
        return Interpreter.#inspectMap(term, opts);

      case "bitstring":
        return Interpreter.#inspectBitstring(term, opts);

      case "list":
        return Interpreter.#inspectList(term, opts);

      case "integer":
        return term.value.toString();

      case "tuple":
        return Interpreter.#inspectTuple(term, opts);

      case "anonymous_function":
        return Interpreter.#inspectAnonymousFunction(term, opts);

      case "float":
        return Interpreter.#inspectFloat(term, opts);

      case "pid":
        return `#PID<${term.segments.join(".")}>`;

      case "reference":
        return Interpreter.#inspectReference(term, opts);

      case "port":
        return `#Port<${term.segments.join(".")}>`;
    }
  }

  // Renders an atom's name in one of the three formats it takes in source: as a
  // literal (:foo), as a key (foo:) or as the name of a remote call (foo).
  // A name that is a plain ASCII identifier renders as it stands, which is what
  // most atoms are - a map key, a struct field, a function name. Every other
  // name is rendered by Macro.inspect_atom/3, the code the server renders atoms
  // with, so what needs quoting is decided there rather than guessed at here.
  // The fast path is verified against the server for every 1-to-3-character
  // name, the words Elixir gives meaning to, and the identifiers real
  // applications use: scripts/inspect_atom/verify_fast_path.exs.
  // Deps: [Macro.inspect_atom/3]
  static inspectAtomAs(sourceFormat, name) {
    if (ATOM_IDENTIFIER_REGEX.test(name)) {
      return ATOM_FAST_PATHS[sourceFormat](name);
    }

    return Bitstring.toText(
      Elixir_Macro["inspect_atom/3"](
        Type.atom(sourceFormat),
        Type.atom(name),
        Type.list(),
      ),
    );
  }

  static inspectModuleJsName(moduleJsName) {
    if (moduleJsName.startsWith("Elixir_")) {
      return moduleJsName.slice(7).replaceAll("_", ".");
    }

    if (moduleJsName === "Erlang") {
      return ":erlang";
    }

    // Starts with "Erlang_"
    return ":" + moduleJsName.slice(7).toLowerCase();
  }

  static isEqual(left, right) {
    if (Type.isNumber(left)) {
      return Type.isNumber(right) && left.value == right.value;
    }

    if (left.type !== right.type) return false;

    switch (left.type) {
      case "list":
        return $.#areListsEqual(left, right);

      case "map":
        return $.#areMapsEqual(left, right);

      case "tuple":
        return $.#areCollectionsItemsEqual(left.data, right.data);

      default:
        return $.isStrictlyEqual(left, right);
    }
  }

  static isMatched(left, right, context) {
    return Interpreter.matchOperator(right, left, context, false) !== false;
  }

  static isStrictlyEqual(left, right) {
    const leftType = left.type;

    if (leftType !== right.type) return false;

    // Cases ordered by expected frequency (most common first)
    switch (leftType) {
      case "atom":
        return left.value === right.value;

      case "map":
        return $.#areMapsStrictlyEqual(left, right);

      case "bitstring":
        return $.#areBitstringsEqual(left, right);

      case "list":
        return $.#areListsStrictlyEqual(left, right);

      case "integer":
        return left.value === right.value;

      case "tuple":
        return $.#areCollectionsItemsStrictlyEqual(left.data, right.data);

      case "anonymous_function":
        return $.#areFunctionsEqual(left, right);

      case "float":
        return left.value === right.value;

      case "pid":
        return $.#areIdentifiersEqual(left, right);

      case "reference":
        return $.#areReferencesEqual(left, right);

      case "port":
        return $.#areIdentifiersEqual(left, right);
    }
  }

  // context.vars.__matched__ keeps track of already pattern matched variables,
  // which enables to fail pattern matching if the variables with the same name
  // are being pattern matched to different values
  // and to update the var values after pattern matching is finished.
  //
  // right param is before left param, because we need the right arg evaluated before left arg.
  static matchOperator(right, left, context, raiseMatchError = true) {
    if (!context.vars.__matched__) {
      context.vars.__matched__ = {};
    }

    if (Interpreter.#hasUnresolvedVariablePattern(right)) {
      return Type.matchPattern(left, right);
    }

    if (left.type === "match_pattern") {
      // The term has to hold against both sides, so a side that doesn't hold
      // fails the whole match, even where failing is answered rather than raised.
      const result = Interpreter.matchOperator(
        right,
        left.right,
        context,
        raiseMatchError,
      );

      if (result === false) {
        return false;
      }

      return Interpreter.matchOperator(
        right,
        left.left,
        context,
        raiseMatchError,
      );
    }

    if (Type.isMatchPlaceholder(left)) {
      return right;
    }

    if (Type.isMatchPlaceholder(right)) {
      return left;
    }

    if (Type.isVariablePattern(left)) {
      return Interpreter.#matchVariablePattern(
        right,
        left,
        context,
        raiseMatchError,
      );
    }

    if (Type.isConsPattern(left)) {
      return Interpreter.#matchConsPattern(
        right,
        left,
        context,
        raiseMatchError,
      );
    }

    if (Type.isBitstringPattern(left)) {
      return Interpreter.#matchBitstringPattern(
        right,
        left,
        context,
        raiseMatchError,
      );
    }

    if (left.type !== right.type) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    if (Type.isList(left) || Type.isTuple(left)) {
      return Interpreter.#matchListOrTuple(
        right,
        left,
        context,
        raiseMatchError,
      );
    }

    if (Type.isMap(left)) {
      return Interpreter.#matchMap(right, left, context, raiseMatchError);
    }

    if (!Interpreter.isStrictlyEqual(left, right)) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    return right;
  }

  static maybeInitModuleProxy(
    moduleExName,
    moduleJsName,
    moduleType = "elixir",
  ) {
    if (!globalThis[moduleJsName]) {
      const handler = {
        get(target, functionArityStr) {
          if (functionArityStr in target) {
            return target[functionArityStr];
          }

          const [functionName, arity] = functionArityStr.split("/");

          Interpreter.raiseUndefinedFunctionError(
            target.__exModule__,
            functionName,
            Number(arity),
          );
        },
      };

      const moduleProxy = new Proxy({}, handler);

      globalThis[moduleJsName] = moduleProxy;

      moduleProxy.__exModule__ =
        moduleType === "erlang"
          ? Type.atom(moduleExName)
          : Type.alias(moduleExName);

      moduleProxy.__exports__ = new Set();
      moduleProxy.__jsBindings__ = new Map();
      moduleProxy.__jsName__ = moduleJsName;
    }
  }

  static moduleExName(alias) {
    return alias.value.slice(7);
  }

  // Based on: Hologram.Compiler.Encoder.encode_as_class_name/1
  static moduleJsName(alias) {
    const aliasStr = Type.isAtom(alias) ? alias.value : alias;

    if (aliasStr === "erlang") {
      return "Erlang";
    }

    let segments = aliasStr.split(/[._]/);

    if (segments[0] !== "Elixir") {
      segments.unshift("Erlang");
    }

    return segments.map((segment) => Utils.capitalize(segment)).join("_");
  }

  static moduleProxy(alias) {
    return globalThis[Interpreter.moduleJsName(alias)];
  }

  // Turns an :error reason into its exception struct, mirroring Elixir's
  // Exception.normalize/3: a struct passes through unchanged, while a bare
  // term (e.g. :badarg) becomes an ArgumentError/ErlangError/... struct. The
  // boxed stacktrace feeds error_info-based message derivation, which reads
  // the raising frame's args and error_info.
  // Deps: [Exception.normalize/3]
  static normalizeError(reason, stacktrace = Type.list()) {
    return Elixir_Exception["normalize/3"](
      Type.atom("error"),
      reason,
      stacktrace,
    );
  }

  static raiseArgumentError(message) {
    Interpreter.raiseError("ArgumentError", message);
  }

  static raiseBadArityError(fun, args) {
    Interpreter.#raiseFieldBearingError("BadArityError", [
      [Type.atom("args"), Type.list(args)],
      [Type.atom("function"), fun],
    ]);
  }

  static raiseBadFunctionError(term) {
    Interpreter.#raiseFieldBearingError("BadFunctionError", [
      [Type.atom("term"), term],
    ]);
  }

  static raiseBadMapError(term) {
    Interpreter.#raiseFieldBearingError("BadMapError", [
      [Type.atom("term"), term],
    ]);
  }

  // Raises the reason attributed the way OTP BIFs report it: the raising
  // frame carries the given identity, the boxed args, and an error_info
  // entry naming the format module. The identity is supplied statically at
  // the raise site, so the frame is present in every environment. It stands
  // in place of the port function's own dispatch frame - the BEAM shows the
  // BIF frame, not both - which also lets it carry a different identity
  // (e.g. :maps.get/2 reporting as :erlang.map_get/2).
  // To keep raise sites small, the reason is given unboxed and args is a
  // plain array of boxed terms. A non-null cause is an unboxed atom planted
  // as the error_info map's cause entry, refining the formatter's diagnosis
  // the way OTP raise sites do (e.g. :binary.replace/4 planting :badopt).
  // The format module defaults to the one the raising module's OTP
  // application defines, so a raise site states it only to depart from that.
  // A null format module omits the error_info entry entirely, for raising
  // identities whose format module isn't carried by the client runtime.
  static raiseBifError(
    reason,
    module,
    functionName,
    args,
    formatModule = BIF_FORMAT_MODULES[module] ?? "erl_stdlib_errors",
    cause = null,
  ) {
    let errorInfo = null;

    if (formatModule !== null) {
      const errorInfoData = [[Type.atom("module"), Type.atom(formatModule)]];

      if (cause !== null) {
        errorInfoData.push([Type.atom("cause"), Type.atom(cause)]);
      }

      errorInfo = Type.map(errorInfoData);
    }

    const raisingFrame = {
      module,
      function: functionName,
      arityOrArgs: Type.list(args),
      file: null,
      line: null,
      errorInfo,
    };

    const error = new HologramBoxedError(Interpreter.#boxErrorReason(reason));

    error.stacktrace = [raisingFrame, ...error.stacktrace.slice(1)];
    error.rederive(Type.list(error.stacktrace.map(CallStack.boxFrame)));

    throw error;
  }

  // Raises the badarg attributed the way the BEAM reports a failed bitstring
  // construction: no frame of its own is added, since the construction runs
  // inline in the enclosing function's body - instead that function's frame
  // gains an error_info entry naming :erl_erts_errors.format_bs_fail/2 and
  // carrying the {segment, type, error, value} cause tuple the formatter
  // diagnoses. When frame tracking is disabled the error_info stands on a
  // frame of its own, so the message still derives.
  static raiseBitstringConstructionError(index, segmentType, errorTag, value) {
    const errorInfo = Type.map([
      [
        Type.atom("cause"),
        Type.tuple([
          Type.integer(index),
          Type.atom(segmentType),
          Type.atom(errorTag),
          value,
        ]),
      ],
      [Type.atom("function"), Type.atom("format_bs_fail")],
      [Type.atom("module"), Type.atom("erl_erts_errors")],
    ]);

    const error = new HologramBoxedError(Type.atom("badarg"));
    const [enclosingFrame, ...outerFrames] = error.stacktrace;

    // The captured frames are shared with the live call stack, so the
    // decoration goes onto a copy - decorating in place would leak the
    // error_info into every later trace taken through that frame.
    const raisingFrame = enclosingFrame
      ? {...enclosingFrame, errorInfo}
      : {
          module: null,
          function: null,
          arityOrArgs: 0,
          file: null,
          line: null,
          errorInfo,
        };

    error.stacktrace = [raisingFrame, ...outerFrames];
    error.rederive(Type.list(error.stacktrace.map(CallStack.boxFrame)));

    throw error;
  }

  static raiseCaseClauseError(term) {
    Interpreter.#raiseFieldBearingError("CaseClauseError", [
      [Type.atom("term"), term],
    ]);
  }

  static raiseCompileError(message) {
    Interpreter.raiseError("CompileError", message);
  }

  // Deps: [:erlang.error/1]
  static raiseError(aliasStr, message) {
    const errorStruct = Type.errorStruct(aliasStr, message);
    Erlang["error/1"](errorStruct);
  }

  // Raises the reason attributed to the caller: the port function's own
  // dispatch frame is dropped from the trace, mirroring the BIFs that the
  // BEAM reports without a frame of their own (e.g. maps:get/3).
  // The reason is given unboxed, as in raiseBifError.
  static raiseFramelessError(reason) {
    const error = new HologramBoxedError(Interpreter.#boxErrorReason(reason));

    error.stacktrace = error.stacktrace.slice(1);
    error.rederive(Type.list(error.stacktrace.map(CallStack.boxFrame)));

    throw error;
  }

  // Raises a FunctionClauseError attributed the way the BEAM reports a
  // clause mismatch in a ported stdlib function: the raising frame carries
  // the given identity with the args (the BEAM puts the failed call's args
  // in the raising frame), or the bare arity when the server-side args are
  // not representable on the client. The struct carries the same identity
  // as semantic fields, so its transpiled message/1 callback derives the
  // text, including the argument listing. The raising frame stands in place
  // of the port function's own dispatch frame, which also lets it carry a
  // different identity (e.g. :sets.union/2 reporting :sets.size/1). A
  // capitalized module names an Elixir module and becomes an alias, like in
  // CallStack.boxFrame().
  static raiseFunctionClauseError(
    module,
    functionName,
    arity,
    args = null,
    clauseHeads = null,
  ) {
    const moduleTerm = Interpreter.#boxFrameIdentity(module);
    const functionTerm = Interpreter.#boxFrameIdentity(functionName);

    const heads =
      args === null
        ? null
        : (clauseHeads ??
          Interpreter.functionClauseHeads(module, functionName, arity));

    const clauses = heads
      ? Interpreter.#blameClauseHeads(heads.clauses, args)
      : null;

    const kind = heads?.visibility === "private" ? "defp" : "def";

    const struct = Type.struct("FunctionClauseError", [
      [Type.atom("__exception__"), Type.boolean(true)],
      [Type.atom("args"), args === null ? Type.nil() : Type.list(args)],
      [Type.atom("arity"), Type.integer(arity)],
      [Type.atom("clauses"), clauses ?? Type.nil()],
      [Type.atom("function"), functionTerm],
      [Type.atom("kind"), clauses ? Type.atom(kind) : Type.nil()],
      [Type.atom("module"), moduleTerm],
    ]);

    const error = new HologramBoxedError(struct);
    const ownFrame = error.stacktrace[0];

    // A raise from the function's own dispatch keeps its file and line - the
    // BEAM reports those for an Elixir-implemented function, and only the args
    // take the arity's place. A port reporting another identity has neither.
    const keepsLocation =
      ownFrame?.module === module && ownFrame?.function === functionName;

    const raisingFrame = {
      module,
      function: functionName,
      arityOrArgs: args === null ? arity : Type.list(args),
      file: keepsLocation ? ownFrame.file : null,
      line: keepsLocation ? ownFrame.line : null,
      errorInfo: null,
    };

    error.stacktrace = [raisingFrame, ...error.stacktrace.slice(1)];
    error.rederive(Type.list(error.stacktrace.map(CallStack.boxFrame)));

    throw error;
  }

  // TODO: delete once every raise site builds a field-bearing struct instead
  // of an eager message.
  static raiseFunctionClauseErrorMsg(message) {
    Interpreter.raiseError("FunctionClauseError", message);
  }

  static raiseMatchError(term) {
    Interpreter.#raiseFieldBearingError("MatchError", [
      [Type.atom("term"), term],
    ]);
  }

  static raiseTryClauseError(term) {
    Interpreter.#raiseFieldBearingError("TryClauseError", [
      [Type.atom("term"), term],
    ]);
  }

  // Raises the way the BEAM reports a call to a function that isn't there. The
  // reason is stated rather than left for the struct's message/1 callback to
  // work out, since the callback asks the module whether it exports
  // module_info/0, which a client module proxy never does.
  static raiseUndefinedFunctionError(
    module,
    functionName,
    arity,
    isModuleAvailable = true,
  ) {
    const reason = isModuleAvailable
      ? "function not exported"
      : "module could not be loaded";

    Interpreter.#raiseFieldBearingError("UndefinedFunctionError", [
      [Type.atom("arity"), Type.integer(arity)],
      [Type.atom("function"), Type.atom(functionName)],
      [Type.atom("message"), Type.nil()],
      [Type.atom("module"), module],
      [Type.atom("reason"), Type.atom(reason)],
    ]);
  }

  static raiseWithClauseError(term) {
    Interpreter.#raiseFieldBearingError("WithClauseError", [
      [Type.atom("term"), term],
    ]);
  }

  static registerJsBindings(bindingsMap) {
    for (const [moduleExName, bindings] of Object.entries(bindingsMap)) {
      const moduleJsName = Interpreter.moduleJsName("Elixir." + moduleExName);
      Interpreter.maybeInitModuleProxy(moduleExName, moduleJsName);

      const jsBindings = globalThis[moduleJsName].__jsBindings__;

      for (const [alias, value] of Object.entries(bindings)) {
        jsBindings.set(alias, value);
      }
    }
  }

  // Derives the error message through the transpiled Exception.message/1 -
  // the same code the server runs - so exceptions with derived messages
  // (message/1 callbacks) produce identical text on both sides.
  // Deps: [Exception.message/1]
  static resolveErrorMessage(struct) {
    return Bitstring.toText(Elixir_Exception["message/1"](struct));
  }

  // Records where execution has reached in the function currently running, so
  // its frame reports the line of the call being made rather than the line the
  // function started at - which is how the BEAM records it. The compiler emits
  // a call to this before each call it encodes, under the stacktraces flag.
  static setFrameLine(line) {
    const frame = CallStack.peek();

    if (frame) {
      frame.line = line;
    }
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update asyncTry().
  static try(
    body,
    rescueClauses,
    catchClauses,
    elseClauses,
    afterBlock,
    context,
  ) {
    try {
      let bodyResult;

      try {
        bodyResult = body(Interpreter.cloneContext(context));
      } catch (error) {
        // Only boxed Elixir failures participate in rescue/catch matching;
        // native JS errors and HologramInterpreterError re-propagate.
        if (!(error instanceof HologramBoxedError)) {
          throw error;
        }

        const rescued = Interpreter.#evaluateRescueClauses(
          rescueClauses,
          error,
          context,
        );

        if (rescued !== NO_MATCH) {
          return rescued;
        }

        const caught = Interpreter.#evaluateCatchClauses(
          catchClauses,
          error,
          context,
        );

        if (caught !== NO_MATCH) {
          return caught;
        }

        // No clause matched - re-propagate the original failure.
        throw error;
      }

      if (elseClauses.length === 0) {
        return bodyResult;
      }

      // The do block succeeded - match its result against the else clauses,
      // raising TryClauseError if none match. Evaluated outside the inner catch,
      // so a failure here is not re-caught by this try (but after still runs).
      return Interpreter.#evaluateMatchingClause(
        bodyResult,
        elseClauses,
        context,
        Interpreter.raiseTryClauseError,
      );
    } finally {
      // The after block always runs (on success, handled failure, or
      // re-propagated failure) and never changes the return value.
      if (afterBlock !== null) {
        afterBlock(Interpreter.cloneContext(context));
      }
    }
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update try().
  static async asyncTry(
    body,
    rescueClauses,
    catchClauses,
    elseClauses,
    afterBlock,
    context,
  ) {
    try {
      let bodyResult;

      try {
        bodyResult = await body(Interpreter.cloneContext(context));
      } catch (error) {
        // Only boxed Elixir failures participate in rescue/catch matching;
        // native JS errors and HologramInterpreterError re-propagate.
        if (!(error instanceof HologramBoxedError)) {
          throw error;
        }

        const rescued = await Interpreter.#asyncEvaluateRescueClauses(
          rescueClauses,
          error,
          context,
        );

        if (rescued !== NO_MATCH) {
          return rescued;
        }

        const caught = await Interpreter.#asyncEvaluateCatchClauses(
          catchClauses,
          error,
          context,
        );

        if (caught !== NO_MATCH) {
          return caught;
        }

        // No clause matched - re-propagate the original failure.
        throw error;
      }

      if (elseClauses.length === 0) {
        return bodyResult;
      }

      // The do block succeeded - match its result against the else clauses,
      // raising TryClauseError if none match. Evaluated outside the inner catch,
      // so a failure here is not re-caught by this try (but after still runs).
      return await Interpreter.#asyncEvaluateMatchingClause(
        bodyResult,
        elseClauses,
        context,
        Interpreter.raiseTryClauseError,
      );
    } finally {
      // The after block always runs (on success, handled failure, or
      // re-propagated failure) and never changes the return value. Awaiting
      // settles an async after block before this function resolves.
      if (afterBlock !== null) {
        await afterBlock(Interpreter.cloneContext(context));
      }
    }
  }

  static updateVarsToMatchedValues(context) {
    Object.assign(context.vars, context.vars.__matched__);
    delete context.vars.__matched__;

    return context;
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update asyncWith().
  static with(body, clauses, elseClauses, context) {
    const originalContext = context;

    // Clauses form a sequential pipeline that aborts on the first failure, so
    // (unlike case) there is no need to clone per clause: a single working copy
    // protects the caller's context, and on failure the accumulated bindings are
    // discarded in favor of the original context (else runs in the pre-with scope).
    context = Interpreter.cloneContext(context);

    for (const clause of clauses) {
      const value = clause.expression(context);

      // A bare clause (e.g. `x = 1`) has no pattern to match against: it commits its
      // own bindings and the pipeline continues to the next clause.
      if (!clause.match) {
        Interpreter.updateVarsToMatchedValues(context);
        continue;
      }

      // A match clause (`pattern <- expression`, optionally guarded) must match the
      // pattern and then satisfy its guards.
      const isPatternMatched = Interpreter.isMatched(
        clause.match,
        value,
        context,
      );

      if (isPatternMatched) {
        Interpreter.updateVarsToMatchedValues(context);
      }

      const isClausePassed =
        isPatternMatched && Interpreter.#evaluateGuards(clause.guards, context);

      // A failed clause ends the pipeline: the unmatched value is routed to the else
      // clauses, which are evaluated in the original, pre-`with` context.
      if (!isClausePassed) {
        return Interpreter.#withElse(
          value,
          elseClauses,
          Interpreter.cloneContext(originalContext),
        );
      }
    }

    return body(context);
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update with().
  static async asyncWith(body, clauses, elseClauses, context) {
    const originalContext = context;

    context = Interpreter.cloneContext(context);

    for (const clause of clauses) {
      const value = await clause.expression(context);

      if (!clause.match) {
        Interpreter.updateVarsToMatchedValues(context);
        continue;
      }

      const isPatternMatched = Interpreter.isMatched(
        clause.match,
        value,
        context,
      );

      if (isPatternMatched) {
        Interpreter.updateVarsToMatchedValues(context);
      }

      const isClausePassed =
        isPatternMatched && Interpreter.#evaluateGuards(clause.guards, context);

      if (!isClausePassed) {
        return await Interpreter.#asyncWithElse(
          value,
          elseClauses,
          Interpreter.cloneContext(originalContext),
        );
      }
    }

    return await body(context);
  }

  static #areBitstringsEqual(bitstring1, bitstring2) {
    if (bitstring1.text !== null && bitstring1.text === bitstring2.text) {
      return true;
    }

    if (bitstring1.leftoverBitCount !== bitstring2.leftoverBitCount) {
      return false;
    }

    Bitstring.maybeSetBytesFromText(bitstring1);
    const bytes1 = bitstring1.bytes;

    Bitstring.maybeSetBytesFromText(bitstring2);
    const bytes2 = bitstring2.bytes;

    if (bytes1.length !== bytes2.length) {
      return false;
    }

    for (let i = 0; i < bytes1.length; i++) {
      if (bytes1[i] !== bytes2[i]) {
        return false;
      }
    }

    return true;
  }

  static #areCollectionsItemsEqual(items1, items2) {
    if (items1.length !== items2.length) return false;

    for (let i = 0; i < items1.length; i++) {
      if (!$.isEqual(items1[i], items2[i])) return false;
    }

    return true;
  }

  static #areCollectionsItemsStrictlyEqual(items1, items2) {
    if (items1.length !== items2.length) return false;

    for (let i = 0; i < items1.length; i++) {
      if (!$.isStrictlyEqual(items1[i], items2[i])) return false;
    }

    return true;
  }

  static #areFunctionsEqual(function1, function2) {
    if (function1.capturedModule === null) return false;

    return (
      function1.capturedModule === function2.capturedModule &&
      function1.capturedFunction === function2.capturedFunction &&
      function1.arity === function2.arity
    );
  }

  static #areIdentifiersEqual(identifier1, identifier2) {
    return (
      $.#areIntegerArraysEqual(identifier1.segments, identifier2.segments) &&
      identifier1.origin === identifier2.origin &&
      identifier1.node === identifier2.node
    );
  }

  static #areIntegerArraysEqual(array1, array2) {
    if (array1.length !== array2.length) return false;

    for (let i = 0; i < array1.length; i++) {
      if (array1[i] !== array2[i]) return false;
    }

    return true;
  }

  static #areListsEqual(list1, list2) {
    return (
      $.#areCollectionsItemsEqual(list1.data, list2.data) &&
      list1.isProper === list2.isProper
    );
  }

  static #areListsStrictlyEqual(list1, list2) {
    return (
      $.#areCollectionsItemsStrictlyEqual(list1.data, list2.data) &&
      list1.isProper === list2.isProper
    );
  }

  static #areMapsEqual(map1, map2) {
    const data1 = map1.data;
    const data2 = map2.data;

    const keys = Object.keys(data1);

    if (keys.length !== Object.keys(data2).length) return false;

    for (let i = 0; i < keys.length; ++i) {
      const key = keys[i];

      if (!(key in data2) || !$.isEqual(data1[key][1], data2[key][1])) {
        return false;
      }
    }

    return true;
  }

  static #areMapsStrictlyEqual(map1, map2) {
    const data1 = map1.data;
    const data2 = map2.data;

    const keys = Object.keys(data1);

    if (keys.length !== Object.keys(data2).length) return false;

    for (let i = 0; i < keys.length; ++i) {
      const key = keys[i];

      if (!(key in data2) || !$.isStrictlyEqual(data1[key][1], data2[key][1])) {
        return false;
      }
    }

    return true;
  }

  static #areReferencesEqual(ref1, ref2) {
    return (
      $.#areIntegerArraysEqual(ref1.idWords, ref2.idWords) &&
      ref1.node === ref2.node &&
      ref1.creation === ref2.creation
    );
  }

  // Binds the boxed form of the stacktrace captured on the error to the
  // stacktrace field of the clause's context - __STACKTRACE__ in rescue/catch
  // clause scope reads it. The field propagates through cloneContext into the
  // clause body's nested closures, while function dispatch builds fresh
  // contexts, so it never leaks into called functions.
  static #bindStacktrace(error, context) {
    context.stacktrace = $.boxStacktrace(error);
  }

  // Recomputes against the actual arguments which parts of a clause head
  // matched - the marking the server's blame does, which no build-time
  // rendering can carry, since it depends on the call.
  static #blameClauseHead(clauseHead, args) {
    const context = Interpreter.buildContext();
    const patterns = clauseHead.params(context);

    const params = clauseHead.blame.params.map((source, index) => {
      const matched = Interpreter.isMatched(
        patterns[index],
        args[index],
        context,
      );

      if (matched) {
        // What a param binds is visible to the params and guards after it,
        // the way the BEAM matches a clause head.
        Interpreter.updateVarsToMatchedValues(context);
      }

      return Interpreter.#blameNode(matched, source);
    });

    const guards = clauseHead.blame.guards.map((guard) =>
      Interpreter.#blameGuard(guard, context),
    );

    return Type.tuple([Type.list(params), Type.list(guards)]);
  }

  // Returns null when the clause heads carry no rendered sources, which is
  // how they arrive with client stacktraces disabled.
  static #blameClauseHeads(clauseHeads, args) {
    if (clauseHeads.length === 0 || !clauseHeads[0].blame) {
      return null;
    }

    return Type.list(
      clauseHeads.map((clauseHead) =>
        Interpreter.#blameClauseHead(clauseHead, args),
      ),
    );
  }

  static #blameGuard(guard, context) {
    if (guard.source !== undefined) {
      return Interpreter.#blameNode(
        Interpreter.#evaluatesToTrue(guard.test, context),
        guard.source,
      );
    }

    return Type.tuple([
      Type.atom(guard.operator),
      Interpreter.#blameGuard(guard.left, context),
      Interpreter.#blameGuard(guard.right, context),
    ]);
  }

  static #blameNode(match, source) {
    return Type.map([
      [Type.atom("match?"), Type.boolean(match)],
      [Type.atom("source"), Type.bitstring(source)],
    ]);
  }

  // Boxes the unboxed reason shorthand the raise helpers accept: a string for
  // an atom reason or a [tag, term] array for a tagged tuple reason.
  static #boxErrorReason(reason) {
    return typeof reason === "string"
      ? Type.atom(reason)
      : Type.tuple([Type.atom(reason[0]), ...reason.slice(1)]);
  }

  // Boxes an identity a frame reports: a capitalized name is an Elixir module
  // alias, an absent one is nil - the way the BEAM reports a function it can't
  // name.
  static #boxFrameIdentity(name) {
    if (name === null) {
      return Type.nil();
    }

    return /^[A-Z]/.test(name) ? Type.alias(name) : Type.atom(name);
  }

  static #buildElixirFunction(
    moduleExName,
    functionName,
    arity,
    visibility,
    clauses,
    file,
  ) {
    return Interpreter.#buildFrameTrackingWrapper(
      moduleExName,
      functionName,
      arity,
      file,
      function () {
        let startTime;

        if (globalThis.Hologram.isProfilingEnabled) {
          startTime = performance.now();
        }

        const mfa = `${moduleExName}.${functionName}/${arity}`;

        // TODO: remove on release
        // Interpreter.#logFunctionCall(mfa, arguments);

        const args = Type.list([...arguments]);

        for (const clause of clauses) {
          const context = Interpreter.buildContext({module: moduleExName});
          const pattern = Type.list(clause.params(context));

          if (Interpreter.isMatched(pattern, args, context)) {
            Interpreter.updateVarsToMatchedValues(context);

            if (Interpreter.#evaluateGuards(clause.guards, context)) {
              // The frame is pushed before clause dispatch, so which line it
              // points at is known only now, once a clause has matched.
              if (globalThis.Hologram.config.stacktraces) {
                CallStack.peek().line = clause.line ?? null;
              }

              const result = clause.body(context);

              // TODO: remove on release
              // Interpreter.#logFunctionResult(mfa, result);

              if (globalThis.Hologram.isProfilingEnabled) {
                console.log(
                  `Hologram: function ${mfa} executed in`,
                  PerformanceTimer.diff(startTime),
                );
              }

              return result;
            }
          }
        }

        // No clause matched, so the loop above never recorded a line. The BEAM
        // reports the first clause, which is where the function starts.
        if (globalThis.Hologram.config.stacktraces) {
          CallStack.peek().line = clauses[0]?.line ?? null;
        }

        Interpreter.raiseFunctionClauseError(
          moduleExName,
          functionName,
          arity,
          [...arguments],
          {visibility, clauses},
        );
      },
    );
  }

  // Wraps a function so each invocation pushes its frame onto the shadow call
  // stack and pops it when the invocation exits, on every exit path - return,
  // raise, or async settlement.
  static #buildFrameTrackingWrapper(
    module,
    functionName,
    arityOrArgs,
    file,
    fn,
  ) {
    return function () {
      // Frame tracking is flag-gated: with client stacktraces off, the only
      // frame an error carries is the raising one, attached at the raise site.
      // The config object is set before any dispatch can run - by the runtime
      // bundle bootstrap in the browser and by the test helpers in tests.
      let popsFrameOnExit = globalThis.Hologram.config.stacktraces;

      if (popsFrameOnExit) {
        CallStack.push({
          module,
          function: functionName,
          arityOrArgs,
          file,
          line: null,
          errorInfo: null,
        });
      }

      try {
        const result = fn(...arguments);

        // An async function is still executing when it returns its promise,
        // so the frame pops when the promise settles instead of on return -
        // otherwise every frame below an await would be gone by the time an
        // error is raised there.
        if (popsFrameOnExit && result instanceof Promise) {
          popsFrameOnExit = false;
          return result.finally(() => CallStack.pop());
        }

        return result;
      } finally {
        if (popsFrameOnExit) {
          CallStack.pop();
        }
      }
    };
  }

  // Lists compare element by element. When the shared elements are equal,
  // the tails decide: a proper list's tail is the empty list, an improper
  // list's tail is its last stored item, and elements remaining in the
  // longer list form a nonempty list tail.
  static #compareLists(list1, list2) {
    const elementCount1 = list1.isProper
      ? list1.data.length
      : list1.data.length - 1;

    const elementCount2 = list2.isProper
      ? list2.data.length
      : list2.data.length - 1;

    const sharedCount = Math.min(elementCount1, elementCount2);

    for (let i = 0; i < sharedCount; ++i) {
      const itemOrder = Interpreter.compareTerms(list1.data[i], list2.data[i]);

      if (itemOrder !== 0) {
        return itemOrder;
      }
    }

    const exhausted1 = elementCount1 === sharedCount;
    const exhausted2 = elementCount2 === sharedCount;

    if (exhausted1 && exhausted2) {
      if (list1.isProper && list2.isProper) return 0;

      // Neither tail is a nonempty list here, so this never recurses
      const tail1 = list1.isProper ? Type.list() : list1.data.at(-1);
      const tail2 = list2.isProper ? Type.list() : list2.data.at(-1);

      return Interpreter.compareTerms(tail1, tail2);
    }

    if (exhausted1) {
      // The empty tail precedes any nonempty list remainder
      if (list1.isProper) return -1;

      return Interpreter.compareTerms(
        list1.data.at(-1),
        Interpreter.#listRemainder(list2, sharedCount),
      );
    }

    if (list2.isProper) return 1;

    return Interpreter.compareTerms(
      Interpreter.#listRemainder(list1, sharedCount),
      list2.data.at(-1),
    );
  }

  static #comparePids(pid1, pid2) {
    for (let i = 2; i >= 0; --i) {
      if (pid1.segments[i] === pid2.segments[i]) {
        continue;
      }

      return pid1.segments[i] < pid2.segments[i] ? -1 : 1;
    }

    return 0;
  }

  static #compareTuples(tuple1, tuple2) {
    if (tuple1.data.length !== tuple2.data.length) {
      return tuple1.data.length < tuple2.data.length ? -1 : 1;
    }

    for (let i = 0; i < tuple1.data.length; ++i) {
      const itemOrder = Interpreter.compareTerms(
        tuple1.data[i],
        tuple2.data[i],
      );

      if (itemOrder !== 0) {
        return itemOrder;
      }
    }

    return 0;
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #asyncEvaluateCatchClauses().
  // Spells printable text the way a string or charlist literal does: the
  // characters that stand for themselves as they are, the rest as escapes.
  static #escapeText(text) {
    return text.replace(TEXT_ESCAPE_REGEX, (match) => {
      if (match === "#{") {
        return "\\#{";
      }

      const codePoint = match.codePointAt(0);

      return (
        TEXT_ESCAPES[codePoint] ??
        `\\u${codePoint.toString(16).toUpperCase().padStart(4, "0")}`
      );
    });
  }

  static #evaluateCatchClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchCatchClause(clause, error, contextClone)) {
        return clause.body(contextClone);
      }
    }

    return NO_MATCH;
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #evaluateCatchClauses().
  static async #asyncEvaluateCatchClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchCatchClause(clause, error, contextClone)) {
        return await clause.body(contextClone);
      }
    }

    return NO_MATCH;
  }

  static #evaluateGuards(guards, context) {
    if (guards.length === 0) {
      return true;
    }

    for (const guard of guards) {
      if (Type.isTrue(guard(context))) {
        return true;
      }
    }

    return false;
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #asyncEvaluateMatchingClause().
  // Evaluates the body of the first clause whose pattern and guards match `value`,
  // raising via `errorFun` if none do. Shared case-clause dispatch: used by case/2
  // and by with's else block (which is itself a case over the unmatched value).
  static #evaluateMatchingClause(value, clauses, context, errorFun) {
    if (typeof value === "function") {
      value = value(context);
    }

    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.isMatched(clause.match, value, contextClone)) {
        Interpreter.updateVarsToMatchedValues(contextClone);

        if (Interpreter.#evaluateGuards(clause.guards, contextClone)) {
          return clause.body(contextClone);
        }
      }
    }

    errorFun(value);
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #evaluateMatchingClause().
  static async #asyncEvaluateMatchingClause(value, clauses, context, errorFun) {
    if (typeof value === "function") {
      value = await value(context);
    }

    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.isMatched(clause.match, value, contextClone)) {
        Interpreter.updateVarsToMatchedValues(contextClone);

        if (Interpreter.#evaluateGuards(clause.guards, contextClone)) {
          return await clause.body(contextClone);
        }
      }
    }

    errorFun(value);
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #asyncEvaluateRescueClauses().
  static #evaluateRescueClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchRescueClause(clause, error, contextClone)) {
        return clause.body(contextClone);
      }
    }

    return NO_MATCH;
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #evaluateRescueClauses().
  static async #asyncEvaluateRescueClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchRescueClause(clause, error, contextClone)) {
        return await clause.body(contextClone);
      }
    }

    return NO_MATCH;
  }

  static #evaluatesToTrue(test, context) {
    try {
      return Type.isTrue(test(context));
    } catch {
      // A guard that raises is a guard that didn't hold, as on the BEAM.
      return false;
    }
  }

  static #handleMatchFail(right, raiseMatchError) {
    if (raiseMatchError) {
      $.raiseMatchError(right);
    }

    return false;
  }

  static #hasUnresolvedVariablePattern(term) {
    const termType = term.type;

    if (
      termType === "anonymous_function" ||
      termType === "atom" ||
      termType === "bitstring" ||
      termType === "float" ||
      termType === "integer" ||
      termType === "match_placeholder"
    ) {
      return false;
    }

    if (termType === "variable_pattern") {
      return true;
    }

    if (termType === "cons_pattern") {
      return (
        Interpreter.#hasUnresolvedVariablePattern(term.head) ||
        Interpreter.#hasUnresolvedVariablePattern(term.tail)
      );
    }

    if (termType === "list" || termType === "tuple") {
      return term.data.some((item) =>
        Interpreter.#hasUnresolvedVariablePattern(item),
      );
    }

    if (termType === "map") {
      for (const [key, value] of Object.values(term.data)) {
        if (
          Interpreter.#hasUnresolvedVariablePattern(key) ||
          Interpreter.#hasUnresolvedVariablePattern(value)
        ) {
          return true;
        }
      }
    }

    if (termType === "match_pattern") {
      return (
        Interpreter.#hasUnresolvedVariablePattern(term.left) ||
        Interpreter.#hasUnresolvedVariablePattern(term.right)
      );
    }

    return false;
  }

  static #inspectAnonymousFunction(term, _opts) {
    if (term.capturedModule) {
      return `&${term.capturedModule}.${term.capturedFunction}/${term.arity}`;
    }

    const moduleName = Interpreter.moduleExName(term.context.module);

    // The two numbers are the fun's index and the uniq of the code it was
    // defined in, taken from the same source :erlang.fun_info/1 reports them.
    const id = `${term.uniq}.${term.uniq}`;

    // A fun defined outside of any function definition carries no name, and is
    // then shown by its defining module alone. The name of the definition it
    // does come from is rendered the way a remote call's is, so one that isn't
    // a valid identifier - a fun defined in a test, say - comes out quoted.
    let definition = "";

    if (term.name !== null) {
      const source = term.name.replace(/^-/, "").replace(/-fun-\d+-$/, "");

      // The arity follows the last slash - what precedes it is the name, which
      // may hold slashes of its own when it needed quoting to be defined.
      const slashIndex = source.lastIndexOf("/");
      const parentName = source.slice(0, slashIndex);
      const parentArity = source.slice(slashIndex + 1);

      definition = `.${Interpreter.inspectAtomAs("remote_call", parentName)}/${parentArity}`;
    }

    return `#Function<${id}/${term.arity} in ${moduleName}${definition}>`;
  }

  static #inspectAtom(term, _opts) {
    if (Type.isBoolean(term) || Type.isNil(term)) {
      return term.value;
    }

    // An alias drops its "Elixir." prefix, unless what follows is Elixir
    // itself - the prefix is then what tells :"Elixir.Elixir" from :Elixir.
    if (ALIAS_REGEX.test(term.value)) {
      const isElixirItself =
        term.value === "Elixir" ||
        term.value === "Elixir.Elixir" ||
        term.value.startsWith("Elixir.Elixir.");

      return isElixirItself ? term.value : $.moduleExName(term);
    }

    return Interpreter.inspectAtomAs("literal", term.value);
  }

  static #inspectBitstring(term, _opts) {
    if (Bitstring.isPrintableText(term)) {
      return `"${Interpreter.#escapeText(term.text)}"`;
    }

    Bitstring.maybeSetBytesFromText(term);

    const {bytes, leftoverBitCount} = term;

    if (leftoverBitCount === 0) {
      return `<<${bytes.join(", ")}>>`;
    }

    const leftoverBitsValue = bytes.at(-1) >>> (8 - leftoverBitCount);
    const leftoverBitsStr = `${leftoverBitsValue}::size(${leftoverBitCount}`;

    if (bytes.length > 1) {
      return `<<${bytes.slice(0, -1).join(", ")}, ${leftoverBitsStr})>>`;
    }

    return `<<${leftoverBitsStr})>>`;
  }

  static #inspectFloat(term, _opts) {
    if (Number.isInteger(term.value)) {
      return term.value.toString() + ".0";
    }

    return term.value.toString();
  }

  static #inspectKeywordList(term, opts) {
    return (
      "[" +
      term.data
        .map(
          (item) =>
            Interpreter.inspect(item.data[0], opts).substring(1) +
            ": " +
            Interpreter.inspect(item.data[1], opts),
        )
        .join(", ") +
      "]"
    );
  }

  static #inspectList(term, opts) {
    if (Interpreter.#isPrintableCharlist(term)) {
      const text = term.data
        .map(({value}) => String.fromCodePoint(Number(value)))
        .join("");

      return `~c"${Interpreter.#escapeText(text)}"`;
    }

    if (term.data.length !== 0 && Type.isKeywordList(term)) {
      return Interpreter.#inspectKeywordList(term, opts);
    }

    if (term.isProper) {
      return (
        "[" +
        term.data.map((elem) => Interpreter.inspect(elem, opts)).join(", ") +
        "]"
      );
    }

    return (
      "[" +
      term.data
        .slice(0, -1)
        .map((elem) => Interpreter.inspect(elem, opts))
        .join(", ") +
      " | " +
      Interpreter.inspect(term.data.slice(-1)[0], opts) +
      "]"
    );
  }

  // TODO: inspect structs
  // Deps: [:lists.sort/1, :maps.to_list/1]
  static #inspectMap(term, opts) {
    if (Type.isRange(term)) {
      return Interpreter.#inspectRange(term, opts);
    }

    const optCustomOptions =
      Interpreter.accessKeywordListElement(opts, Type.atom("custom_options")) ||
      Type.keywordList();

    const optSortMaps =
      Interpreter.accessKeywordListElement(
        optCustomOptions,
        Type.atom("sort_maps"),
      ) || Type.boolean(false);

    if (Type.isTrue(optSortMaps)) {
      term = Type.map(
        Erlang_Lists["sort/1"](Erlang_Maps["to_list/1"](term)).data.map(
          (tuple) => tuple.data,
        ),
      );
    }

    // Mirrors Inspect.List.keyword?/1: an alias key keeps the whole map in the
    // "key => value" form, since Foo: would read as the atom :Foo, not Foo.
    const isAtomKeyMap = Object.values(term.data).every(
      ([key, _value]) => Type.isAtom(key) && !Type.isAlias(key),
    );

    let itemsStr = "";

    if (isAtomKeyMap) {
      itemsStr = Object.values(term.data)
        .map(
          ([key, value]) =>
            `${Interpreter.inspectAtomAs("key", key.value)} ${Interpreter.inspect(value, opts)}`,
        )
        .join(", ");
    } else {
      itemsStr = Object.values(term.data)
        .map(
          ([key, value]) =>
            `${Interpreter.inspect(key, opts)} => ${Interpreter.inspect(
              value,
              opts,
            )}`,
        )
        .join(", ");
    }

    return "%{" + itemsStr + "}";
  }

  // Deps: [:maps.get/2]
  static #inspectRange(term, opts) {
    const first = Erlang_Maps["get/2"](Type.atom("first"), term);
    const last = Erlang_Maps["get/2"](Type.atom("last"), term);
    const step = Erlang_Maps["get/2"](Type.atom("step"), term);

    const stepStr =
      step.value > 1 ? `//${Interpreter.inspect(step, opts)}` : "";

    return `${Interpreter.inspect(first, opts)}..${Interpreter.inspect(last, opts)}${stepStr}`;
  }

  static #inspectReference(term, _opts) {
    const localIncarnationId = NodeTable.getLocalIncarnationId(
      term.node,
      term.creation,
    );

    return `#Reference<${localIncarnationId}.${term.idWords.toReversed().join(".")}>`;
  }

  static #inspectTuple(term, opts) {
    return (
      "{" +
      term.data.map((elem) => Interpreter.inspect(elem, opts)).join(", ") +
      "}"
    );
  }

  // Mirrors List.ascii_printable?/1 on a proper, nonempty list: 7..13 are the
  // characters "\a\b\t\n\v\f\r", 27 is "\e", and 32..126 are the printable
  // ASCII ones. Such a list is what Elixir shows as a charlist.
  static #isPrintableCharlist(term) {
    if (!term.isProper || term.data.length === 0) {
      return false;
    }

    return term.data.every(
      (item) =>
        item.type === "integer" &&
        ((item.value >= 7n && item.value <= 13n) ||
          item.value === 27n ||
          (item.value >= 32n && item.value <= 126n)),
    );
  }

  // Returns the nonempty list formed by the list's items from the given
  // index on, preserving an improper tail.
  static #listRemainder(list, fromIndex) {
    const data = list.data.slice(fromIndex);

    return list.isProper ? Type.list(data) : Type.improperList(data);
  }

  // TODO: reenable when debug mode is implemented
  // static #logFunctionCall(mfa, args) {
  //   Console.startGroup(mfa);

  //   if (args.length > 0) {
  //     Console.printHeader("args");

  //     for (let i = 0; i < args.length; ++i) {
  //       Console.printDataItem(i + 1, args[i]);
  //     }
  //   }
  // }

  // TODO: reenable when debug mode is implemented
  // static #logFunctionResult(mfa, result) {
  //   Console.printHeader("result");
  //   Console.printData(result);
  //   Console.endGroup(mfa);
  // }

  static #matchBitstringPattern(right, left, context, raiseMatchError) {
    if (right.type !== "bitstring" && right.type !== "bitstring_pattern") {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    let chunkOffset = 0;
    const rightBitCount = Bitstring.calculateBitCount(right);

    for (let i = 0; i < left.segments.length; i++) {
      const segment = left.segments[i];
      const segmentType = segment.type;
      const isLastSegment = i === left.segments.length - 1;

      if (segmentType === "utf16" || segmentType === "utf32") {
        const message =
          "Pattern matching on bitstring segments with utf16 and utf32 type modifiers is not yet implemented in Hologram";

        throw new HologramInterpreterError(message);
      }

      let chunkBitCount;

      // A utf8 segment is as wide as the sequence it matches, so what it
      // consumes is known only by reading that sequence. Anything that isn't
      // one code point there is a failed match, as on the BEAM.
      if (segmentType === "utf8") {
        chunkBitCount = Bitstring.utf8SegmentBitCount(right, chunkOffset);

        if (chunkBitCount === null) {
          return $.#handleMatchFail(right, raiseMatchError);
        }
      } else if (
        // Special case: last segment with binary or bitstring type and no explicit size
        // should consume all remaining bits
        isLastSegment &&
        (segmentType === "binary" || segmentType === "bitstring") &&
        segment.size === null
      ) {
        chunkBitCount = rightBitCount - chunkOffset;
      } else {
        chunkBitCount = Bitstring.calculateSegmentBitCount(segment);

        if (chunkBitCount === null) {
          return $.#handleMatchFail(right, raiseMatchError);
        }
      }

      if (
        segment.type === "float" &&
        chunkBitCount !== 16 &&
        chunkBitCount !== 32 &&
        chunkBitCount !== 64
      ) {
        return $.#handleMatchFail(right, raiseMatchError);
      }

      if (chunkOffset + chunkBitCount > rightBitCount) {
        return $.#handleMatchFail(right, raiseMatchError);
      }

      const chunk = Bitstring.takeChunk(right, chunkOffset, chunkBitCount);

      if (segment.value.type === "variable_pattern") {
        const decodedChunk = Bitstring.decodeSegmentChunk(segment, chunk);
        Interpreter.matchOperator(
          decodedChunk,
          segment.value,
          context,
          raiseMatchError,
        );
      } else if (segment.value.type === "match_placeholder") {
        // Match placeholder in bitstring patterns just consumes the chunk without binding
        // This is equivalent to _ in Elixir bitstring patterns
      } else {
        const segmentBitstring = Bitstring.fromSegments([segment]);

        if (!Interpreter.isStrictlyEqual(segmentBitstring, chunk)) {
          return $.#handleMatchFail(right, raiseMatchError);
        }
      }

      chunkOffset += chunkBitCount;
    }

    if (chunkOffset !== rightBitCount) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    return right;
  }

  static #matchCatchClause(clause, error, context) {
    // Match the kind pattern against the error's kind atom and the value pattern
    // against the error's raw value, in the same context so the bindings are
    // shared, then evaluate the guards against the committed bindings.
    if (
      Interpreter.isMatched(clause.kind, error.kind, context) &&
      Interpreter.isMatched(clause.value, error.value, context)
    ) {
      Interpreter.updateVarsToMatchedValues(context);

      if (Interpreter.#evaluateGuards(clause.guards, context)) {
        Interpreter.#bindStacktrace(error, context);
        return true;
      }
    }

    return false;
  }

  // Deps: [:erlang.hd/1, :erlang.tl/1]
  static #matchConsPattern(right, left, context, raiseMatchError) {
    if (!Type.isList(right) || right.data.length === 0) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    if (
      Type.isList(left.tail) &&
      Type.isProperList(left.tail) !== Type.isProperList(right)
    ) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    const rightHead = Erlang["hd/1"](right);
    const rightTail = Erlang["tl/1"](right);

    if (
      !Interpreter.isMatched(left.head, rightHead, context) ||
      !Interpreter.isMatched(left.tail, rightTail, context)
    ) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    return right;
  }

  static #matchListOrTuple(right, left, context, raiseMatchError) {
    const count = left.data.length;

    if (left.data.length !== right.data.length) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    if (Type.isList(left) && left.isProper !== right.isProper) {
      return $.#handleMatchFail(right, raiseMatchError);
    }

    for (let i = 0; i < count; ++i) {
      if (!Interpreter.isMatched(left.data[i], right.data[i], context)) {
        return $.#handleMatchFail(right, raiseMatchError);
      }
    }

    return right;
  }

  static #matchMap(right, left, context, raiseMatchError) {
    for (const [key, value] of Object.entries(left.data)) {
      if (
        typeof right.data[key] === "undefined" ||
        !Interpreter.isMatched(value[1], right.data[key][1], context)
      ) {
        return $.#handleMatchFail(right, raiseMatchError);
      }
    }

    return right;
  }

  // Deps: [:maps.get/2]
  static #matchRescueClause(clause, error, context) {
    // rescue only catches :error-kind failures. An error normally carries its
    // reason's normalized exception form - a bare reason like :badarg has
    // become an ArgumentError/ErlangError/... via Exception.normalize/3 - so
    // its __struct__ alone decides matching.
    if (error.kind.value !== "error") {
      return false;
    }

    // An error that arrived while another one was deriving, or whose derivation
    // faulted, has no normalized form (see HologramBoxedError). Which exception
    // it is was never established, so no clause claims it: it keeps travelling,
    // carrying the fault named in its message, rather than being rescued into a
    // shape no clause body could read.
    if (error.struct === null) {
      return false;
    }

    // A bare `rescue e ->` (empty modules) catches any exception; otherwise the
    // exception struct's module must be one of the listed modules.
    if (clause.modules.length > 0) {
      const structModule = Erlang_Maps["get/2"](
        Type.atom("__struct__"),
        error.struct,
      );

      const isModuleMatched = clause.modules.some((module) =>
        Interpreter.isStrictlyEqual(module, structModule),
      );

      if (!isModuleMatched) {
        return false;
      }
    }

    // Bind the rescued exception struct to the clause variable, if present.
    if (clause.variable !== null) {
      Interpreter.isMatched(clause.variable, error.struct, context);
      Interpreter.updateVarsToMatchedValues(context);
    }

    Interpreter.#bindStacktrace(error, context);

    return true;
  }

  static #matchVariablePattern(right, left, context, raiseMatchError) {
    if (context.vars.__matched__[left.name]) {
      if (
        !Interpreter.isStrictlyEqual(context.vars.__matched__[left.name], right)
      ) {
        return $.#handleMatchFail(right, raiseMatchError);
      }
    } else {
      context.vars.__matched__[left.name] = right;
    }

    return right;
  }

  static #raiseCondClauseError() {
    Interpreter.#raiseFieldBearingError("CondClauseError", []);
  }

  // Raises an exception struct carrying semantic fields and no :message -
  // the message text derives at format time through the exception module's
  // transpiled message/1 callback, the same code the server runs.
  // Deps: [:erlang.error/1]
  static #raiseFieldBearingError(aliasStr, fields) {
    const struct = Type.struct(aliasStr, [
      [Type.atom("__exception__"), Type.boolean(true)],
      ...fields,
    ]);

    Erlang["error/1"](struct);
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #asyncWalkComprehension().
  // Deps: [Enum.to_list/1]
  static #walkComprehension(qualifiers, index, context, onLeaf) {
    if (index === qualifiers.length) {
      onLeaf(context);
      return;
    }

    const qualifier = qualifiers[index];

    if (qualifier.type === "filter") {
      if (Type.isTruthy(qualifier.filter(context))) {
        Interpreter.#walkComprehension(qualifiers, index + 1, context, onLeaf);
      }

      return;
    }

    if (qualifier.type === "bitstring_generator") {
      const source = qualifier.body(context);

      if (!Type.isBitstring(source)) {
        Erlang["error/1"](Type.tuple([Type.atom("bad_generator"), source]));
      }

      // Appending a rest segment makes the exact-match bitstring pattern machinery
      // match only the prefix. The $ character is illegal in Elixir identifiers,
      // so the $rest name can't collide with user variables.
      const restSegment = Type.bitstringSegment(Type.variablePattern("$rest"), {
        type: "bitstring",
      });

      const prefixPattern = Type.bitstringPattern([
        ...qualifier.match.segments,
        restSegment,
      ]);

      let remaining = source;

      while (true) {
        const contextClone = Interpreter.cloneContext(context);

        if (!Interpreter.isMatched(prefixPattern, remaining, contextClone)) {
          break;
        }

        remaining = contextClone.vars.__matched__["$rest"];
        delete contextClone.vars.__matched__["$rest"];

        Interpreter.updateVarsToMatchedValues(contextClone);

        Interpreter.#walkComprehension(
          qualifiers,
          index + 1,
          contextClone,
          onLeaf,
        );
      }

      return;
    }

    const list = Elixir_Enum["to_list/1"](qualifier.body(context)).data;

    for (const item of list) {
      const contextClone = Interpreter.cloneContext(context);

      if (!Interpreter.isMatched(qualifier.match, item, contextClone)) {
        continue;
      }

      Interpreter.updateVarsToMatchedValues(contextClone);

      if (!Interpreter.#evaluateGuards(qualifier.guards, contextClone)) {
        continue;
      }

      Interpreter.#walkComprehension(
        qualifiers,
        index + 1,
        contextClone,
        onLeaf,
      );
    }
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #walkComprehension().
  // Deps: [Enum.to_list/1]
  static async #asyncWalkComprehension(qualifiers, index, context, onLeaf) {
    if (index === qualifiers.length) {
      await onLeaf(context);
      return;
    }

    const qualifier = qualifiers[index];

    if (qualifier.type === "filter") {
      if (Type.isTruthy(await qualifier.filter(context))) {
        await Interpreter.#asyncWalkComprehension(
          qualifiers,
          index + 1,
          context,
          onLeaf,
        );
      }

      return;
    }

    if (qualifier.type === "bitstring_generator") {
      const source = await qualifier.body(context);

      if (!Type.isBitstring(source)) {
        Erlang["error/1"](Type.tuple([Type.atom("bad_generator"), source]));
      }

      // Appending a rest segment makes the exact-match bitstring pattern machinery
      // match only the prefix. The $ character is illegal in Elixir identifiers,
      // so the $rest name can't collide with user variables.
      const restSegment = Type.bitstringSegment(Type.variablePattern("$rest"), {
        type: "bitstring",
      });

      const prefixPattern = Type.bitstringPattern([
        ...qualifier.match.segments,
        restSegment,
      ]);

      let remaining = source;

      while (true) {
        const contextClone = Interpreter.cloneContext(context);

        if (!Interpreter.isMatched(prefixPattern, remaining, contextClone)) {
          break;
        }

        remaining = contextClone.vars.__matched__["$rest"];
        delete contextClone.vars.__matched__["$rest"];

        Interpreter.updateVarsToMatchedValues(contextClone);

        await Interpreter.#asyncWalkComprehension(
          qualifiers,
          index + 1,
          contextClone,
          onLeaf,
        );
      }

      return;
    }

    const list = Elixir_Enum["to_list/1"](await qualifier.body(context)).data;

    for (const item of list) {
      const contextClone = Interpreter.cloneContext(context);

      if (!Interpreter.isMatched(qualifier.match, item, contextClone)) {
        continue;
      }

      Interpreter.updateVarsToMatchedValues(contextClone);

      if (!Interpreter.#evaluateGuards(qualifier.guards, contextClone)) {
        continue;
      }

      await Interpreter.#asyncWalkComprehension(
        qualifiers,
        index + 1,
        contextClone,
        onLeaf,
      );
    }
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #asyncWithElse().
  static #withElse(value, elseClauses, context) {
    // A `with` without else clauses returns the unmatched value as-is.
    if (elseClauses.length === 0) {
      return value;
    }

    return Interpreter.#evaluateMatchingClause(
      value,
      elseClauses,
      context,
      Interpreter.raiseWithClauseError,
    );
  }

  // SYNC/ASYNC PAIR: When modifying this function, also update #withElse().
  static async #asyncWithElse(value, elseClauses, context) {
    // A `with` without else clauses returns the unmatched value as-is.
    if (elseClauses.length === 0) {
      return value;
    }

    return await Interpreter.#asyncEvaluateMatchingClause(
      value,
      elseClauses,
      context,
      Interpreter.raiseWithClauseError,
    );
  }
}

const $ = Interpreter;
