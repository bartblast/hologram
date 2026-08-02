"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// Elixir renders the attempted clauses from the ASTs it reads out of BEAM debug
// info. The client has no ASTs - its clause nodes carry the source the compiler
// rendered at build time - so message/1 is ported rather than transpiled, and
// reads those sources in place of Macro.to_string/1 calls.
const Elixir_FunctionClauseError = {
  // Deps: [Exception.format_mfa/3]
  "message/1": (struct) => {
    // TODO: drop once no raise site builds an eager message.
    const messageEntry = struct.data["atom(message)"];

    if (messageEntry !== undefined) {
      return messageEntry[1];
    }

    const functionTerm = struct.data["atom(function)"][1];

    if (Type.isNil(functionTerm)) {
      return Type.bitstring("no function clause matches");
    }

    const module = struct.data["atom(module)"][1];
    const arity = struct.data["atom(arity)"][1];

    const mfa = Bitstring.toText(
      Elixir_Exception["format_mfa/3"](module, functionTerm, arity),
    );

    const args = struct.data["atom(args)"][1];

    if (Type.isNil(args)) {
      return Type.bitstring(`no function clause matching in ${mfa}`);
    }

    const functionName = functionTerm.value;
    const kind = struct.data["atom(kind)"][1];
    const clauses = struct.data["atom(clauses)"][1];

    const argsText = args.data.reduce(
      (acc, arg, index) =>
        `${acc}\n    # ${index + 1}\n    ${indent(Interpreter.inspect(arg))}\n`,
      `\n\nThe following arguments were given to ${mfa}:\n`,
    );

    const clausesText = renderClauses(clauses, kind, functionName);

    return Type.bitstring(
      `no function clause matching in ${mfa}${argsText}${clausesText}`,
    );
  },
};

// Elixir shows at most this many attempted clauses, counting the rest out.
const CLAUSE_LIMIT = 10;

// Kernel's and/or precedences, which decide where the rendering parenthesizes.
const PRECEDENCES = {and: 130, or: 120};

// Mirrors the padding Elixir applies to each listed argument. Nothing inspect
// renders holds a newline of its own - every one it could show is escaped - so
// this only takes effect if inspect ever breaks a wide term across lines.
function indent(text) {
  return text.replaceAll("\n", "\n    ");
}

function renderClause(clause, kind, functionName) {
  const [params, guards] = clause.data;
  const paramsText = params.data.map(renderNode).join(", ");

  const guardsText = guards.data.reduce(
    (acc, guard) => `${acc} when ${renderGuard(guard, 0)}`,
    "",
  );

  return `    ${kind.value} ${functionName}(${paramsText})${guardsText}\n`;
}

function renderClauses(clauses, kind, functionName) {
  if (Type.isNil(clauses) || clauses.data.length === 0) {
    return "";
  }

  const shownClauses = clauses.data.slice(0, CLAUSE_LIMIT);

  const header = `\nAttempted function clauses (showing ${shownClauses.length} out of ${clauses.data.length}):\n\n`;

  const clausesText = shownClauses
    .map((clause) => renderClause(clause, kind, functionName))
    .join("");

  const hiddenCount = clauses.data.length - CLAUSE_LIMIT;

  const hiddenText =
    hiddenCount > 0
      ? `    ...\n    (${hiddenCount} ${hiddenCount === 1 ? "clause" : "clauses"} not shown)\n`
      : "";

  return `${header}${clausesText}${hiddenText}`;
}

function renderGuard(guard, parentPrecedence) {
  if (!Type.isTuple(guard)) {
    return renderNode(guard);
  }

  const [operator, left, right] = guard.data;
  const precedence = PRECEDENCES[operator.value];

  const text = `${renderGuard(left, precedence)} ${operator.value} ${renderGuard(right, precedence)}`;

  return parentPrecedence > precedence ? `(${text})` : text;
}

// The parts that didn't match are wrapped in dashes, the way the server marks
// them.
function renderNode(node) {
  const source = Bitstring.toText(node.data["atom(source)"][1]);

  return Type.isTrue(node.data["atom(match?)"][1]) ? source : `-${source}-`;
}

export default Elixir_FunctionClauseError;
