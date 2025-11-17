"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Property lists are lists of tuples or atoms
// Examples: [{key1, value1}, {key2, value2}] or [atom1, {key2, value2}]

const Erlang_Proplists = {
  // Start get_value/2
  "get_value/2": (key, list) => {
    return Erlang_Proplists["get_value/3"](key, list, Type.atom("undefined"));
  },
  // End get_value/2
  // Deps: [:proplists.get_value/3]

  // Start get_value/3
  "get_value/3": (key, list, defaultValue) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    for (const item of list.data) {
      // Check for {Key, Value} tuple
      if (Type.isTuple(item) && item.data.length >= 2) {
        const itemKey = item.data[0];
        if (Interpreter.compareTerms(key, itemKey) === 0) {
          return item.data[1];
        }
      }
      // Check for bare atom matching the key (value is true)
      else if (Type.isAtom(item) && Interpreter.compareTerms(key, item) === 0) {
        return Type.boolean(true);
      }
    }

    return defaultValue;
  },
  // End get_value/3
  // Deps: []

  // Start get_keys/1
  "get_keys/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    const keys = [];
    const seenKeys = new Set();

    for (const item of list.data) {
      let key = null;

      // Check for {Key, Value} tuple
      if (Type.isTuple(item) && item.data.length >= 2) {
        key = item.data[0];
      }
      // Check for bare atom
      else if (Type.isAtom(item)) {
        key = item;
      }

      if (key !== null) {
        const encodedKey = Type.encodeMapKey(key);
        if (!seenKeys.has(encodedKey)) {
          seenKeys.add(encodedKey);
          keys.push(key);
        }
      }
    }

    return Type.list(keys);
  },
  // End get_keys/1
  // Deps: []

  // Start get_all_values/2
  "get_all_values/2": (key, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    const values = [];

    for (const item of list.data) {
      // Check for {Key, Value} tuple
      if (Type.isTuple(item) && item.data.length >= 2) {
        const itemKey = item.data[0];
        if (Interpreter.compareTerms(key, itemKey) === 0) {
          values.push(item.data[1]);
        }
      }
    }

    return Type.list(values);
  },
  // End get_all_values/2
  // Deps: []

  // Start delete/2
  "delete/2": (key, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    const result = [];
    let found = false;

    for (const item of list.data) {
      let matches = false;

      // Check for {Key, Value} tuple
      if (Type.isTuple(item) && item.data.length >= 2) {
        const itemKey = item.data[0];
        if (!found && Interpreter.compareTerms(key, itemKey) === 0) {
          matches = true;
          found = true;
        }
      }
      // Check for bare atom
      else if (Type.isAtom(item) && !found && Interpreter.compareTerms(key, item) === 0) {
        matches = true;
        found = true;
      }

      if (!matches) {
        result.push(item);
      }
    }

    return Type.list(result);
  },
  // End delete/2
  // Deps: []

  // Start lookup/2
  "lookup/2": (key, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    for (const item of list.data) {
      // Check for {Key, Value} tuple
      if (Type.isTuple(item) && item.data.length >= 2) {
        const itemKey = item.data[0];
        if (Interpreter.compareTerms(key, itemKey) === 0) {
          return item;
        }
      }
      // Check for bare atom
      else if (Type.isAtom(item) && Interpreter.compareTerms(key, item) === 0) {
        return item;
      }
    }

    return Type.atom("none");
  },
  // End lookup/2
  // Deps: []
};

export default Erlang_Proplists;
