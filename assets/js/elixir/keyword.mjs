"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Keyword lists are lists of {key, value} tuples where keys are atoms

function isKeywordList(term) {
  if (!Type.isList(term)) {
    return false;
  }

  for (const item of term.data) {
    if (!Type.isTuple(item) || item.data.length !== 2) {
      return false;
    }
    if (!Type.isAtom(item.data[0])) {
      return false;
    }
  }

  return true;
}

const Elixir_Keyword = {
  // Start get/2
  "get/2": (keywords, key) => {
    return Elixir_Keyword["get/3"](keywords, key, Type.atom("nil"));
  },
  // End get/2
  // Deps: [Keyword.get/3]

  // Start get/3
  "get/3": (keywords, key, defaultValue) => {
    if (!isKeywordList(keywords)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a keyword list"),
      );
    }

    if (!Type.isAtom(key)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    for (const item of keywords.data) {
      const itemKey = item.data[0];
      if (itemKey.value === key.value) {
        return item.data[1];
      }
    }

    return defaultValue;
  },
  // End get/3
  // Deps: []

  // Start has_key?/2
  "has_key?/2": (keywords, key) => {
    if (!isKeywordList(keywords)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a keyword list"),
      );
    }

    if (!Type.isAtom(key)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    for (const item of keywords.data) {
      const itemKey = item.data[0];
      if (itemKey.value === key.value) {
        return Type.boolean(true);
      }
    }

    return Type.boolean(false);
  },
  // End has_key?/2
  // Deps: []

  // Start keys/1
  "keys/1": (keywords) => {
    if (!isKeywordList(keywords)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a keyword list"),
      );
    }

    const keys = keywords.data.map((item) => item.data[0]);
    return Type.list(keys);
  },
  // End keys/1
  // Deps: []

  // Start values/1
  "values/1": (keywords) => {
    if (!isKeywordList(keywords)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a keyword list"),
      );
    }

    const values = keywords.data.map((item) => item.data[1]);
    return Type.list(values);
  },
  // End values/1
  // Deps: []

  // Start delete/2
  "delete/2": (keywords, key) => {
    if (!isKeywordList(keywords)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a keyword list"),
      );
    }

    if (!Type.isAtom(key)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    const result = keywords.data.filter((item) => {
      return item.data[0].value !== key.value;
    });

    return Type.list(result);
  },
  // End delete/2
  // Deps: []

  // Start put/3
  "put/3": (keywords, key, value) => {
    if (!isKeywordList(keywords)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a keyword list"),
      );
    }

    if (!Type.isAtom(key)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Remove existing entries with this key, then add new one
    const filtered = keywords.data.filter((item) => {
      return item.data[0].value !== key.value;
    });

    filtered.push(Type.tuple([key, value]));

    return Type.list(filtered);
  },
  // End put/3
  // Deps: []

  // Start merge/2
  "merge/2": (keywords1, keywords2) => {
    if (!isKeywordList(keywords1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a keyword list"),
      );
    }

    if (!isKeywordList(keywords2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a keyword list"),
      );
    }

    // Start with keywords1, then add/override with keywords2
    const keySet = new Set();
    const result = [];

    // First, collect all keys from keywords2
    for (const item of keywords2.data) {
      keySet.add(item.data[0].value);
    }

    // Add items from keywords1 that aren't overridden
    for (const item of keywords1.data) {
      if (!keySet.has(item.data[0].value)) {
        result.push(item);
      }
    }

    // Add all items from keywords2
    result.push(...keywords2.data);

    return Type.list(result);
  },
  // End merge/2
  // Deps: []

  // Start new/0
  "new/0": () => {
    return Type.list([]);
  },
  // End new/0
  // Deps: []
};

export default Elixir_Keyword;
