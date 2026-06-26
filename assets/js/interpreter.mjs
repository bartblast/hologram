"use strict";

import Bitstring from "./bitstring.mjs";
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

export default class Interpreter {
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
      !Type.isPid(term) &&
      !Type.isTuple(term)
    ) {
      const message = `Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: ${Interpreter.inspect(
        term,
      )}`;

      throw new HologramInterpreterError(message);
    }
  }

  // Keep this message in sync with build_argument_error_msg in Hologram.Commons.TestUtils.
  static buildArgumentErrorMsg(argumentIndex, message) {
    const ordinal = Utils.ordinal(argumentIndex);

    return `errors were found at the given arguments:\n\n  * ${ordinal} argument: ${message}\n`;
  }

  // Keep this message in sync with build_bad_function_error_msg in Hologram.Commons.TestUtils.
  static buildBadFunctionErrorMsg(term) {
    return "expected a function, got: " + $.inspect(term);
  }

  // Keep this message in sync with build_bad_map_error_msg in Hologram.Commons.TestUtils.
  static buildBadMapErrorMsg(arg) {
    return "expected a map, got:\n\n    " + Interpreter.inspect(arg) + "\n";
  }

  // Keep this message in sync with build_case_clause_error_msg in Hologram.Commons.TestUtils.
  static buildCaseClauseErrorMsg(arg) {
    return "no case clause matching:\n\n    " + Interpreter.inspect(arg) + "\n";
  }

  static buildContext(data = {}) {
    const {module, vars} = data;
    const context = {module: null, vars: {}};

    if (module) {
      context.module = Type.isAlias(module) ? module : Type.alias(module);
    }

    if (vars) {
      context.vars = vars;
    }

    return context;
  }

  // Keep this message in sync with build_erlang_error_msg in Hologram.Commons.TestUtils.
  static buildErlangErrorMsg(message) {
    return `Erlang error: ${message}`;
  }

  // TODO: include attempted function clauses info
  // Keep this message in sync with build_function_clause_error_msg in Hologram.Commons.TestUtils.
  static buildFunctionClauseErrorMsg(funName, args = null) {
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
  static buildKeyErrorMsg(key, map) {
    const opts = Type.keywordList([
      [
        Type.atom("custom_options"),
        Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
      ],
    ]);

    return `key ${Interpreter.inspect(key)} not found in:\n\n    ${Interpreter.inspect(map, opts)}\n`;
  }

  // Keep this message in sync with build_match_error_msg in Hologram.Commons.TestUtils.
  static buildMatchErrorMsg(right) {
    return (
      "no match of right hand side value:\n\n    " +
      Interpreter.inspect(right) +
      "\n"
    );
  }

  // Hologram-specific, no server-side equivalent.
  static buildTooBigOutputErrorMsg(mfa) {
    return (
      `${mfa} can't be transpiled automatically to JavaScript, because its output is too big.\n` +
      "See what to do here: https://www.hologram.page/TODO"
    );
  }

  // Keep this message in sync with build_undefined_function_error_msg in Hologram.Commons.TestUtils.
  static buildUndefinedFunctionErrorMsg(
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
  static buildWithClauseErrorMsg(arg) {
    return "no with clause matching:\n\n    " + Interpreter.inspect(arg) + "\n";
  }

  // callAnonymousFunction() has no unit tests in interpreter_test.mjs, only:
  // * feature tests in test/features/test/function_calls/anonymous_function_test.exs,
  // * feature tests in test/features/test/function_calls/function_capture_test.exs,
  // * consistency tests in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call anonymous function section).
  // * consistency tests in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call function capture section).
  // Unit test maintenance in interpreter_test.mjs would be problematic because tests would need to be updated
  // each time Hologram.Compiler.Encoder's implementation changes.
  static callAnonymousFunction(fun, argsArray) {
    if (argsArray.length !== fun.arity) {
      Interpreter.raiseBadArityError(fun.arity, argsArray);
    }

    const args = Type.list(argsArray);

    for (const clause of fun.clauses) {
      const contextClone = Interpreter.cloneContext(fun.context);
      const pattern = Type.list(clause.params(contextClone));

      if (Interpreter.isMatched(pattern, args, contextClone)) {
        Interpreter.updateVarsToMatchedValues(contextClone);

        if (Interpreter.#evaluateGuards(clause.guards, contextClone)) {
          return clause.body(contextClone);
        }
      }
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(
        `anonymous fn/${fun.arity}`,
        argsArray,
      ),
    );
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
        Interpreter.buildUndefinedFunctionErrorMsg(
          module,
          functionName.value,
          arity,
          false,
        ),
      );
    }

    if (
      moduleProxy.__exports__ &&
      !moduleProxy.__exports__.has(functionArityStr) &&
      !Interpreter.isEqual(module, context.module)
    ) {
      Interpreter.raiseUndefinedFunctionError(
        Interpreter.buildUndefinedFunctionErrorMsg(
          module,
          functionName.value,
          arity,
        ),
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
    return {module: context.module, vars: {...context.vars}};
  }

  // Implements structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // TODO: support comparing the remaining types: anonymous function, list, map, port, reference
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
        clauses,
      );

    if (visibility === "public") {
      globalThis[moduleJsName].__exports__.add(`${functionName}/${arity}`);
    }
  }

  static defineErlangFunction(moduleExName, functionName, arity, jsFunction) {
    const moduleJsName = Interpreter.moduleJsName(moduleExName);
    const functionArityStr = `${functionName}/${arity}`;

    Interpreter.maybeInitModuleProxy(moduleExName, moduleJsName, "erlang");

    globalThis[moduleJsName][functionArityStr] = jsFunction;
    globalThis[moduleJsName].__exports__.add(functionArityStr);
  }

  static defineManuallyPortedFunction(
    moduleExName,
    functionArityStr,
    visibility,
    fun,
  ) {
    const moduleJsName = Interpreter.moduleJsName("Elixir." + moduleExName);

    Interpreter.maybeInitModuleProxy(moduleExName, moduleJsName);

    globalThis[moduleJsName][functionArityStr] = fun;

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

  static getErrorType(jsError) {
    // TODO: use transpiled Elixir code
    return jsError.struct.data["atom(__struct__)"][1].value.substring(7);
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
      if (Type.isNumber(right)) {
        return left.value == right.value;
      } else {
        return false;
      }
    }

    return $.isStrictlyEqual(left, right);
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
        return $.#areMapsEqual(left, right);

      case "bitstring":
        return $.#areBitstringsEqual(left, right);

      case "list":
        return $.#areListsEqual(left, right);

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
      return {type: "match_pattern", left: left, right: right};
    }

    if (left.type === "match_pattern") {
      Interpreter.matchOperator(right, left.right, context, raiseMatchError);
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
            Interpreter.buildUndefinedFunctionErrorMsg(
              target.__exModule__,
              functionName,
              arity,
            ),
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

  static raiseArgumentError(message) {
    Interpreter.raiseError("ArgumentError", message);
  }

  static raiseArithmeticError(blame = null) {
    Interpreter.raiseError(
      "ArithmeticError",
      `bad argument in arithmetic expression${blame ? `: ${blame}` : ""}`,
    );
  }

  static raiseBadArityError(arity, args) {
    const numArgs = args.length === 0 ? "no" : args.length;

    const argumentNounPluralized = Utils.naiveNounPlural(
      "argument",
      args.length,
    );

    const inspectedArgs = args.map((arg) => Interpreter.inspect(arg));

    let maybeInspectedArgs = "";
    if (args.length > 0) {
      maybeInspectedArgs = ` (${inspectedArgs.join(", ")})`;
    }

    Interpreter.raiseError(
      "BadArityError",
      `anonymous function with arity ${arity} called with ${numArgs} ${argumentNounPluralized}${maybeInspectedArgs}`,
    );
  }

  static raiseBadFunctionError(term) {
    $.raiseError("BadFunctionError", $.buildBadFunctionErrorMsg(term));
  }

  static raiseBadMapError(arg) {
    Interpreter.raiseError("BadMapError", Interpreter.buildBadMapErrorMsg(arg));
  }

  static raiseCaseClauseError(arg) {
    Interpreter.raiseError(
      "CaseClauseError",
      Interpreter.buildCaseClauseErrorMsg(arg),
    );
  }

  static raiseCompileError(message) {
    Interpreter.raiseError("CompileError", message);
  }

  static raiseErlangError(message) {
    Interpreter.raiseError("ErlangError", message);
  }

  // Deps: [:erlang.error/1]
  static raiseError(aliasStr, message) {
    const errorStruct = Type.errorStruct(aliasStr, message);
    Erlang["error/1"](errorStruct);
  }

  static raiseFunctionClauseError(message) {
    Interpreter.raiseError("FunctionClauseError", message);
  }

  static raiseKeyError(message) {
    Interpreter.raiseError("KeyError", message);
  }

  static raiseMatchError(message) {
    Interpreter.raiseError("MatchError", message);
  }

  static raiseUndefinedFunctionError(message) {
    Interpreter.raiseError("UndefinedFunctionError", message);
  }

  static raiseWithClauseError(arg) {
    Interpreter.raiseError(
      "WithClauseError",
      Interpreter.buildWithClauseErrorMsg(arg),
    );
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

  // TODO: consider when porting Elixir error handling
  static resolveErrorMessage(struct) {
    const messageEntry = struct.data["atom(message)"];

    if (messageEntry !== undefined) {
      return Bitstring.toText(messageEntry[1]);
    }

    return $.inspect(struct);
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

      // TODO: handle else clauses
      throw new HologramInterpreterError(
        '"try" expression else clauses are not yet implemented in Hologram',
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

        const rescued = await Interpreter.#evaluateRescueClauses(
          rescueClauses,
          error,
          context,
        );

        if (rescued !== NO_MATCH) {
          return rescued;
        }

        const caught = await Interpreter.#evaluateCatchClauses(
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

      // TODO: handle else clauses
      throw new HologramInterpreterError(
        '"try" expression else clauses are not yet implemented in Hologram',
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
      $.#areCollectionsItemsStrictlyEqual(list1.data, list2.data) &&
      list1.isProper === list2.isProper
    );
  }

  static #areMapsEqual(map1, map2) {
    const data1 = map1.data;
    const data2 = map2.data;

    if (data1.length !== data2.length) return false;

    const keys = Object.keys(data1);

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

  static #buildElixirFunction(moduleExName, functionName, arity, clauses) {
    return function () {
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

      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(mfa, arguments),
      );
    };
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

  // TODO: add async variant for use in asyncTry() once try/rescue is fully implemented.
  static #evaluateCatchClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchCatchClause(clause, error, contextClone)) {
        return clause.body(contextClone);
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

  // TODO: add async variant for use in asyncTry() once try/rescue is fully implemented.
  static #evaluateRescueClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchRescueClause(clause, error, contextClone)) {
        return clause.body(contextClone);
      }
    }

    return NO_MATCH;
  }

  static #handleMatchFail(right, raiseMatchError) {
    if (raiseMatchError) {
      $.raiseMatchError($.buildMatchErrorMsg(right));
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

    return `anonymous function fn/${term.arity}`;
  }

  // TODO: handle correctly atoms which need to be double quoted, e.g. :"1"
  static #inspectAtom(term, _opts) {
    if (Type.isBoolean(term) || Type.isNil(term)) {
      return term.value;
    }

    if (Type.isAlias(term)) {
      return $.moduleExName(term);
    }

    return ":" + term.value;
  }

  static #inspectBitstring(term, _opts) {
    if (Bitstring.isPrintableText(term)) {
      return '"' + term.text.replace(/"/g, '\\"') + '"';
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

    const isAtomKeyMap = Object.values(term.data).every(([key, _value]) =>
      Type.isAtom(key),
    );

    let itemsStr = "";

    if (isAtomKeyMap) {
      itemsStr = Object.values(term.data)
        .map(
          ([key, value]) => `${key.value}: ${Interpreter.inspect(value, opts)}`,
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

      if (
        segmentType === "utf8" ||
        segmentType === "utf16" ||
        segmentType === "utf32"
      ) {
        const message =
          "Pattern matching on bitstring segments with utf* type modifiers is not yet implemented in Hologram";

        throw new HologramInterpreterError(message);
      }

      let chunkBitCount;

      // Special case: last segment with binary or bitstring type and no explicit size
      // should consume all remaining bits
      if (
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

  static #matchCatchClause(_clause, _error, _context) {
    // TODO: handle catch clauses
    throw new HologramInterpreterError(
      '"try" expression catch clauses are not yet implemented in Hologram',
    );
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

  static #matchRescueClause(_clause, _error, _context) {
    // TODO: handle rescue clauses
    throw new HologramInterpreterError(
      '"try" expression rescue clauses are not yet implemented in Hologram',
    );
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
    Interpreter.raiseError(
      "CondClauseError",
      "no cond clause evaluated to a truthy value",
    );
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
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_generator, ${Interpreter.inspect(source)}}`,
          ),
        );
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
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_generator, ${Interpreter.inspect(source)}}`,
          ),
        );
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
