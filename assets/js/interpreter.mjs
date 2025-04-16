"use strict";

import isEqual from "lodash/isEqual.js";
import uniqWith from "lodash/uniqWith.js";

import Bitstring from "./bitstring.mjs";
import Bitstring2 from "./bitstring2.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import PerformanceTimer from "./performance_timer.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

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
      !Type.isFloat(term) &&
      !Type.isInteger(term) &&
      !Type.isPid(term) &&
      !Type.isTuple(term)
    ) {
      const message = `Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: ${Interpreter.inspect(
        term,
      )}`;

      throw new HologramInterpreterError(message);
    }
  }

  static buildArgumentErrorMsg(argumentIndex, message) {
    const ordinal = Utils.ordinal(argumentIndex);

    return `errors were found at the given arguments:\n\n  * ${ordinal} argument: ${message}\n`;
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

  static buildErlangErrorMsg(message) {
    return `Erlang error: ${message}`;
  }

  // TODO: include attempted function clauses info
  static buildFunctionClauseErrorMsg(funName, args = []) {
    let argsInfo = "";

    if (args.length > 0) {
      argsInfo = Array.from(args).reduce(
        (acc, arg, idx) =>
          `${acc}\n    # ${idx + 1}\n    ${Interpreter.inspect(arg)}\n`,
        `\n\nThe following arguments were given to ${funName}:\n`,
      );
    }

    return `no function clause matching in ${funName}${argsInfo}`;
  }

  static buildKeyErrorMsg(key, map) {
    const opts = Type.keywordList([
      [
        Type.atom("custom_options"),
        Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
      ],
    ]);

    return `key ${Interpreter.inspect(key)} not found in: ${Interpreter.inspect(map, opts)}`;
  }

  static buildMatchErrorMsg(right) {
    return "no match of right hand side value: " + Interpreter.inspect(right);
  }

  static buildTooBigOutputErrorMsg(mfa) {
    return (
      `${mfa} can't be transpiled automatically to JavaScript, because its output is too big.\n` +
      "See what to do here: https://www.hologram.page/TODO"
    );
  }

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
    const moduleRef = Interpreter.moduleRef(module);
    const arity = args.data.length;
    const functionArityStr = `${functionName.value}/${arity}`;

    if (typeof moduleRef === "undefined") {
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
      !moduleRef.__exports__.has(functionArityStr) &&
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

    return moduleRef[functionArityStr](...args.data);
  }

  // case() has no unit tests in interpreter_test.mjs, only feature tests in test/features/test/control_flow/case_test.exs
  // Unit test maintenance in interpreter_test.mjs would be problematic because tests would need to be updated
  // each time Hologram.Compiler.Encoder's implementation changes.
  static case(condition, clauses, context) {
    if (typeof condition === "function") {
      condition = condition(context);
    }

    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.isMatched(clause.match, condition, contextClone)) {
        Interpreter.updateVarsToMatchedValues(contextClone);

        if (Interpreter.#evaluateGuards(clause.guards, contextClone)) {
          return clause.body(contextClone);
        }
      }
    }

    Interpreter.raiseCaseClauseError(condition);
  }

  static cloneContext(context) {
    // Use {...obj} instead of Object.assign({}, obj) for shallow copying,
    // see benchmarks here: https://thecodebarbarian.com/object-assign-vs-object-spread.html
    return {module: context.module, vars: {...context.vars}};
  }

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
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

      case "pid":
        return Interpreter.#comparePids(term1, term2);

      case "tuple":
        return Interpreter.#compareTuples(term1, term2);
    }
  }

  // Deps: [Enum.into/2, Enum.to_list/1]
  static comprehension(
    generators,
    filters,
    collectable,
    unique,
    mapper,
    context,
  ) {
    const generatorsCount = generators.length;

    const sets = generators.map(
      (generator) => Elixir_Enum["to_list/1"](generator.body(context)).data,
    );

    let items = Utils.cartesianProduct(sets).reduce((acc, combination) => {
      const contextClone = Interpreter.cloneContext(context);

      for (let i = 0; i < generatorsCount; ++i) {
        if (
          Interpreter.isMatched(
            generators[i].match,
            combination[i],
            contextClone,
          )
        ) {
          Interpreter.updateVarsToMatchedValues(contextClone);

          if (Interpreter.#evaluateGuards(generators[i].guards, contextClone)) {
            continue;
          }
        }

        return acc;
      }

      for (const filter of filters) {
        if (Type.isFalsy(filter(contextClone))) {
          return acc;
        }
      }

      acc.push(mapper(contextClone));
      return acc;
    }, []);

    if (unique) {
      items = uniqWith(items, Interpreter.isStrictlyEqual);
    }

    return Elixir_Enum["into/2"](Type.list(items), collectable);
  }

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

    globalThis[moduleJsName][`${functionName}/${arity}`] = function () {
      let startTime;

      if (globalThis.hologram.isProfilingEnabled) {
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

            if (globalThis.hologram.isProfilingEnabled) {
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

    if (visibility === "public") {
      globalThis[moduleJsName].__exports__.add(`${functionName}/${arity}`);
    }
  }

  static defineErlangFunction(moduleExName, functionName, arity, jsFunction) {
    const moduleJsName = Interpreter.moduleJsName(moduleExName);

    if (!globalThis[moduleJsName]) {
      globalThis[moduleJsName] = {};
    }

    globalThis[moduleJsName][`${functionName}/${arity}`] = jsFunction;
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

    if (!globalThis[moduleJsName]) {
      globalThis[moduleJsName] = {};
    }

    globalThis[moduleJsName][`${functionName}/${arity}`] = () => {
      // TODO: update the URL
      const message = `Function :${moduleExName}.${functionName}/${arity} is not yet ported. See what to do here: https://www.hologram.page/TODO`;

      throw new HologramInterpreterError(message);
    };
  }

  // Deps: [:maps.get/2]
  static dotOperator(left, right) {
    // if left argument is a boxed atom, treat the operator as a remote function call
    if (Type.isAtom(left)) {
      const functionArityStr = `${right.value}/0`;
      return Interpreter.moduleRef(left)[functionArityStr]();
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

  static getErrorMessage(jsError) {
    // TODO: use transpiled Elixir code
    return Bitstring.toText(jsError.struct.data["atom(message)"][1]);
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

  // TODO: implement other types (e.g. ports, structs)
  // TODO: implement opts param
  static inspect(term, opts = Type.keywordList()) {
    switch (term.type) {
      case "anonymous_function":
        return Interpreter.#inspectAnonymousFunction(term, opts);

      case "atom":
        return Interpreter.#inspectAtom(term, opts);

      case "bitstring":
        return Interpreter.#inspectBitstring(term, opts);

      case "bitstring2":
        return Interpreter.#inspectBitstring2(term, opts);

      case "float":
        return Interpreter.#inspectFloat(term, opts);

      case "integer":
        return term.value.toString();

      case "list":
        return Interpreter.#inspectList(term, opts);

      case "map":
        return Interpreter.#inspectMap(term, opts);

      case "pid":
        return `#PID<${term.segments.join(".")}>`;

      case "string":
        return `"${term.value}"`;

      case "tuple":
        return Interpreter.#inspectTuple(term, opts);

      // TODO: remove when all types are supported
      default:
        return Serializer.serialize(term, true, false);
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

    return isEqual(left, right);
  }

  static isMatched(left, right, context) {
    try {
      Interpreter.matchOperator(right, left, context);
      return true;
    } catch {
      return false;
    }
  }

  static isStrictlyEqual(left, right) {
    if (left.type !== right.type) {
      return false;
    }

    return isEqual(left, right);
  }

  // context.vars.__matched__ keeps track of already pattern matched variables,
  // which enables to fail pattern matching if the variables with the same name
  // are being pattern matched to different values
  // and to update the var values after pattern matching is finished.
  //
  // right param is before left param, because we need the right arg evaluated before left arg.
  static matchOperator(right, left, context) {
    if (!context.vars.__matched__) {
      context.vars.__matched__ = {};
    }

    if (Interpreter.#hasUnresolvedVariablePattern(right)) {
      return {type: "match_pattern", left: left, right: right};
    }

    if (left.type === "match_pattern") {
      Interpreter.matchOperator(right, left.right, context);
      return Interpreter.matchOperator(right, left.left, context);
    }

    if (Type.isMatchPlaceholder(left)) {
      return right;
    }

    if (Type.isVariablePattern(left)) {
      return Interpreter.#matchVariablePattern(right, left, context);
    }

    if (Type.isConsPattern(left)) {
      return Interpreter.#matchConsPattern(right, left, context);
    }

    if (Type.isBitstringPattern(left)) {
      return Interpreter.#matchBitstringPattern(right, left, context);
    }

    if (left.type !== right.type) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    if (Type.isList(left) || Type.isTuple(left)) {
      return Interpreter.#matchListOrTuple(right, left, context);
    }

    if (Type.isMap(left)) {
      return Interpreter.#matchMap(right, left, context);
    }

    if (!Interpreter.isStrictlyEqual(left, right)) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    return right;
  }

  static maybeInitModuleProxy(moduleExName, moduleJsName) {
    if (!globalThis[moduleJsName]) {
      const handler = {
        get(moduleRef, functionArityStr) {
          if (functionArityStr in moduleRef) {
            return moduleRef[functionArityStr];
          }

          const [functionName, arity] = functionArityStr.split("/");

          Interpreter.raiseUndefinedFunctionError(
            Interpreter.buildUndefinedFunctionErrorMsg(
              moduleRef.__exModule__,
              functionName,
              arity,
            ),
          );
        },
      };

      globalThis[moduleJsName] = new Proxy({}, handler);
      globalThis[moduleJsName].__exModule__ = Type.alias(moduleExName);
      globalThis[moduleJsName].__exports__ = new Set();
      globalThis[moduleJsName].__jsName__ = moduleJsName;
    }
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

  static moduleRef(alias) {
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

  static raiseBadMapError(arg) {
    const message = "expected a map, got: " + Interpreter.inspect(arg);

    Interpreter.raiseError("BadMapError", message);
  }

  static raiseCaseClauseError(arg) {
    const message = "no case clause matching: " + Interpreter.inspect(arg);

    Interpreter.raiseError("CaseClauseError", message);
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

  static try(
    body,
    rescueClauses,
    catchClauses,
    elseClauses,
    afterBlock,
    context,
  ) {
    let result;

    try {
      const contextClone = Interpreter.cloneContext(context);
      result = body(contextClone);
      // TODO: finish
      // eslint-disable-next-line no-useless-catch
    } catch (error) {
      throw error;

      // TODO: handle errors
      // eslint-disable-next-line no-unreachable
      result =
        Interpreter.#evaluateRescueClauses(rescueClauses, error, context) ||
        Interpreter.#evaluateCatchClauses(catchClauses, error, context);
    } finally {
      // TODO: handle after block
      if (afterBlock) {
        // eslint-disable-next-line no-unsafe-finally
        throw new HologramInterpreterError(
          '"try" expression after block is not yet implemented in Hologram',
        );
      }
    }

    if (elseClauses.length === 0) {
      return result;
    } else {
      // TODO: handle else clauses
      throw new HologramInterpreterError(
        '"try" expression else clauses are not yet implemented in Hologram',
      );
    }
  }

  static updateVarsToMatchedValues(context) {
    Object.assign(context.vars, context.vars.__matched__);
    delete context.vars.__matched__;

    return context;
  }

  // TODO: finish implementing
  static with() {
    throw new HologramInterpreterError(
      '"with" expression is not yet implemented in Hologram',
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

  static #evaluateCatchClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchCatchClause(clause, error, contextClone)) {
        return clause.body(contextClone);
      }
    }

    return false;
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

  static #evaluateRescueClauses(clauses, error, context) {
    for (const clause of clauses) {
      const contextClone = Interpreter.cloneContext(context);

      if (Interpreter.#matchRescueClause(clause, error, contextClone)) {
        return clause.body(contextClone);
      }
    }

    return false;
  }

  static #hasUnresolvedVariablePattern(term) {
    if (
      [
        "anonymous_function",
        "atom",
        "bitstring",
        "float",
        "integer",
        "match_placeholder",
      ].includes(term.type)
    ) {
      return false;
    }

    if (term.type === "variable_pattern") {
      return true;
    }

    if (term.type === "cons_pattern") {
      return (
        Interpreter.#hasUnresolvedVariablePattern(term.head) ||
        Interpreter.#hasUnresolvedVariablePattern(term.tail)
      );
    }

    if (term.type === "list" || term.type === "tuple") {
      return term.data.some((item) =>
        Interpreter.#hasUnresolvedVariablePattern(item),
      );
    }

    if (term.type === "map") {
      for (const [key, value] of Object.values(term.data)) {
        if (
          Interpreter.#hasUnresolvedVariablePattern(key) ||
          Interpreter.#hasUnresolvedVariablePattern(value)
        ) {
          return true;
        }
      }
    }

    if (term.type === "match_pattern") {
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
      return term.value.slice(7);
    }

    return ":" + term.value;
  }

  static #inspectBitstring(term, _opts) {
    if (Bitstring.isPrintableText(term)) {
      return '"' + Bitstring.toText(term) + '"';
    }

    const segmentStrs = Utils.chunkArray(term.bits, 8).map((bits) => {
      const value = Bitstring.buildUnsignedBigIntFromBitArray(bits).toString();
      return bits.length === 8 ? value : `${value}::size(${bits.length})`;
    });

    return `<<${segmentStrs.join(", ")}>>`;
  }

  static #inspectBitstring2(term, _opts) {
    if (Bitstring2.isPrintableText(term)) {
      return '"' + term.text.replace(/"/g, '\\"') + '"';
    }

    Bitstring2.maybeSetBytesFromText(term);

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

  static #matchBitstringPattern(right, left, context) {
    if (right.type !== "bitstring" && right.type !== "bitstring_pattern") {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    let offset = 0;

    for (const segment of left.segments) {
      if (segment.value.type === "variable_pattern") {
        const valueInfo = Bitstring.buildValueFromBitstringChunk(
          segment,
          right.bits,
          offset,
        );

        if (!valueInfo) {
          Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
        }

        const [value, segmentLen] = valueInfo;
        Interpreter.matchOperator(value, segment.value, context);
        offset += segmentLen;
      } else {
        const segmentBitstring = Type.bitstring([segment]);
        const segmentLen = segmentBitstring.bits.length;

        if (right.bits.length - offset < segmentLen) {
          Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
        }

        for (let i = 0; i < segmentLen; ++i) {
          if (segmentBitstring.bits[i] !== right.bits[offset + i]) {
            Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
          }
        }

        offset += segmentLen;
      }
    }

    if (offset < right.bits.length) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
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
  static #matchConsPattern(right, left, context) {
    if (!Type.isList(right) || right.data.length === 0) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    if (
      Type.isList(left.tail) &&
      Type.isProperList(left.tail) !== Type.isProperList(right)
    ) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    const rightHead = Erlang["hd/1"](right);
    const rightTail = Erlang["tl/1"](right);

    if (
      !Interpreter.isMatched(left.head, rightHead, context) ||
      !Interpreter.isMatched(left.tail, rightTail, context)
    ) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    return right;
  }

  static #matchListOrTuple(right, left, context) {
    const count = left.data.length;

    if (left.data.length !== right.data.length) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    if (Type.isList(left) && left.isProper !== right.isProper) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
    }

    for (let i = 0; i < count; ++i) {
      if (!Interpreter.isMatched(left.data[i], right.data[i], context)) {
        Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
      }
    }

    return right;
  }

  static #matchMap(right, left, context) {
    for (const [key, value] of Object.entries(left.data)) {
      if (
        typeof right.data[key] === "undefined" ||
        !Interpreter.isMatched(value[1], right.data[key][1], context)
      ) {
        Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
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

  static #matchVariablePattern(right, left, context) {
    if (context.vars.__matched__[left.name]) {
      if (
        !Interpreter.isStrictlyEqual(context.vars.__matched__[left.name], right)
      ) {
        Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(right));
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
}
