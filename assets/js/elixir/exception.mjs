"use strict";

import Bitstring from "../bitstring.mjs";
import ERTS from "../erts.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// Renders a stacktrace as Elixir renders it. Ported rather than transpiled
// because the transpiled form costs milliseconds per frame - a frame is a
// handful of interpolations, and each one is a String.Chars dispatch several
// interpreted calls deep - and because the branch reading the calling process's
// own stacktrace pulls Process.info/2 and the whole Enumerable.slice family
// into every bundle for a call the client can't make.
//
// IMPORTANT!
// Every shape rendered here is Elixir's. Each is held against what Elixir
// really renders in
// test/elixir/hologram/ex_js_consistency/elixir/exception_test.exs, whose cases
// are twinned by test/javascript/elixir/exception_test.mjs.
// Always update all three together.

// The name a generated anonymous function was defined under, and that
// function's arity, or null when the name isn't one Elixir generated for an
// anonymous function - it generates others, comprehensions among them, and
// those name no function they came from.
function extractAnonymousFunParent(name) {
  const match = /^-(.+)\/(\d+)-fun-\d+-$/.exec(name);

  return match === null ? null : {arity: match[2], name: match[1]};
}

// What a frame says was passed: the arity when that is all it kept, and the
// arguments themselves when it kept those.
function formatArity(arityOrArgs) {
  if (Type.isList(arityOrArgs)) {
    const args = arityOrArgs.data.map((arg) => Interpreter.inspect(arg));

    return `(${args.join(", ")})`;
  }

  return `/${arityOrArgs.value}`;
}

// The application a module's code was compiled into. A module the bundle
// carries no metadata for names none, the way :application.get_application/1
// answers :undefined for one it doesn't know.
function formatApplication(moduleTerm) {
  // An Elixir module is keyed by its name without the Elixir prefix, an Erlang
  // one by the atom it is - the way each is keyed when its metadata is emitted.
  const key = Type.isAlias(moduleTerm)
    ? Interpreter.moduleExName(moduleTerm)
    : moduleTerm.value;

  const app = ERTS.moduleMetadata[key]?.app;

  if (!app) {
    return "";
  }

  const version = ERTS.appVersions[app];

  return version ? `(${app} ${version}) ` : `(${app}) `;
}

// An anonymous function, named by the value it is rather than by a module.
function formatFa(funTerm, arityOrArgs) {
  return `${Interpreter.inspect(funTerm)}${formatArity(arityOrArgs)}`;
}

// A location's file is a charlist, the way the BEAM writes one.
function charlistToText(charlist) {
  const codePoints = charlist.data.map(({value}) => Number(value));

  return String.fromCodePoint(...codePoints);
}

// A file and where in it, each dropped once the one before it is missing - a
// line of zero counts as missing, as it does on the BEAM.
function formatFileLine(file, line, column) {
  if (file === null) {
    return "";
  }

  if (line === null || line === 0n) {
    return `${file}: `;
  }

  if (column === null || column === 0n) {
    return `${file}:${line}: `;
  }

  return `${file}:${line}:${column}: `;
}

// Where a frame happened, as far as it knows.
function formatLocation(location) {
  const value = (key) =>
    location.data.find(
      (entry) => Type.isTuple(entry) && entry.data[0].value === key,
    )?.data[1];

  const file = value("file");
  const line = value("line");
  const column = value("column");

  return formatFileLine(
    file === undefined ? null : charlistToText(file),
    line === undefined ? null : line.value,
    column === undefined ? null : column.value,
  );
}

// What was running in a frame. An anonymous function is named after the one it
// was defined in, since that is the name whoever reads the frame knows it by -
// and the arity it reports is its own, not that function's.
function formatMfa(moduleTerm, functionTerm, arityOrArgs) {
  const moduleText = Interpreter.inspect(moduleTerm);
  const parent = extractAnonymousFunParent(functionTerm.value);

  if (parent !== null) {
    const parentName = Interpreter.inspectAtomAs("remote_call", parent.name);

    return (
      `anonymous fn${formatArity(arityOrArgs)} in ` +
      `${moduleText}.${parentName}/${parent.arity}`
    );
  }

  const name = Interpreter.inspectAtomAs("remote_call", functionTerm.value);

  return `${moduleText}.${name}${formatArity(arityOrArgs)}`;
}

// A single frame, in the shapes Elixir renders one in. The two naming
// __MODULE__ and the one naming __FILE__ come from code the compiler generates,
// and name no application.
function formatStacktraceEntry(frame) {
  if (frame.data.length === 3) {
    const [funTerm, arityOrArgs, location] = frame.data;

    return formatLocation(location) + formatFa(funTerm, arityOrArgs);
  }

  const [moduleTerm, functionTerm, arityOrArgs, location] = frame.data;
  const functionName = functionTerm.value;
  const arity = arityOrArgs.value;

  if (functionName === "__MODULE__" && arity === 0n) {
    return `${formatLocation(location)}${Interpreter.inspect(moduleTerm)} (module)`;
  }

  if (functionName === "__MODULE__" && arity === 1n) {
    return `${formatLocation(location)}(module)`;
  }

  if (functionName === "__FILE__" && arity === 1n) {
    return `${formatLocation(location)}(file)`;
  }

  return (
    formatApplication(moduleTerm) +
    formatLocation(location) +
    formatMfa(moduleTerm, functionTerm, arityOrArgs)
  );
}

const Elixir_Exception = {
  // Deps: [Macro.inspect_atom/3]
  "format_stacktrace/1": (stacktrace) => {
    // Elixir reads the calling process's own stacktrace when given none. The
    // client has no such stacktrace to read: what it keeps is a shadow call
    // stack of its own, which isn't the same thing and isn't what a caller
    // asking for this would get on the server.
    if (!Type.isList(stacktrace)) {
      throw new HologramInterpreterError(
        "Exception.format_stacktrace/1 needs a stacktrace on the client - the " +
          "one Elixir reads from the calling process when given none isn't " +
          "kept there. Pass __STACKTRACE__ or a stacktrace of your own.",
      );
    }

    if (stacktrace.data.length === 0) {
      return Bitstring.fromText("\n");
    }

    const entries = stacktrace.data.map((frame) =>
      formatStacktraceEntry(frame),
    );

    return Bitstring.fromText(`    ${entries.join("\n    ")}\n`);
  },
};

export default Elixir_Exception;
