"use strict";

import ERTS from "./erts.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

// The parts Elixir renders a stack frame in, kept apart rather than joined.
//
// Exception.format_stacktrace/1 joins them into the line the server prints. The
// error overlay reads them as they are, giving each its own tone - which is why
// they are worked out here rather than inside the rendering: an overlay reading
// the rendered line back would be reading a shape Elixir owns, and telling
// where a location ends and what was running begins is exactly what it can't do
// reliably from text.

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

// A location's file is a charlist, the way the BEAM writes one.
function charlistToText(charlist) {
  const codePoints = charlist.data.map(({value}) => Number(value));

  return String.fromCodePoint(...codePoints);
}

// A file and where in it, each dropped once the one before it is missing - a
// line or column of zero counts as missing, as it does on the BEAM.
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

export default class Stacktrace {
  // The application a module's code was compiled into, or null when the bundle
  // carries no metadata for it - which is what :application.get_application/1
  // answers :undefined for on the server.
  static appOf(moduleTerm) {
    // An Elixir module is keyed by its name without the Elixir prefix, an
    // Erlang one by the atom it is - the way each is keyed when its metadata is
    // emitted.
    const key = Type.isAlias(moduleTerm)
      ? Interpreter.moduleExName(moduleTerm)
      : moduleTerm.value;

    return ERTS.moduleMetadata[key]?.app ?? null;
  }

  // A frame in the parts it reads in: the application it came from, where in
  // the source it was, and what was running there. Joined in that order, they
  // are the line Exception.format_stacktrace_entry/1 writes.
  //
  // The entries naming __MODULE__ and __FILE__ come from code the compiler
  // generates, and the three-element one names a function value rather than a
  // module and a name. None of them names an application.
  static frameParts(frame) {
    if (frame.data.length === 3) {
      const [funTerm, arityOrArgs, location] = frame.data;

      return {
        app: "",
        appName: null,
        location: formatLocation(location),
        running: `${Interpreter.inspect(funTerm)}${formatArity(arityOrArgs)}`,
      };
    }

    const [moduleTerm, functionTerm, arityOrArgs, location] = frame.data;
    const functionName = functionTerm.value;
    const arity = arityOrArgs.value;

    const generated = {
      app: "",
      appName: null,
      location: formatLocation(location),
    };

    if (functionName === "__MODULE__" && arity === 0n) {
      return {
        ...generated,
        running: `${Interpreter.inspect(moduleTerm)} (module)`,
      };
    }

    if (functionName === "__MODULE__" && arity === 1n) {
      return {...generated, running: "(module)"};
    }

    if (functionName === "__FILE__" && arity === 1n) {
      return {...generated, running: "(file)"};
    }

    const appName = $.appOf(moduleTerm);
    const version = appName === null ? null : ERTS.appVersions[appName];

    let app = "";

    if (appName !== null) {
      app = version ? `(${appName} ${version}) ` : `(${appName}) `;
    }

    return {
      app,
      appName,
      location: formatLocation(location),
      running: formatMfa(moduleTerm, functionTerm, arityOrArgs),
    };
  }
}

const $ = Stacktrace;
