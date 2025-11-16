"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Global ETS table registry
const etsTables = new Map();
let nextTableId = 1;

class EtsTable {
  constructor(name, options) {
    this.name = name;
    this.id = nextTableId++;
    this.ref = Type.reference(`#Ref<0.0.${this.id}.0>`);
    this.type = "set"; // set, ordered_set, bag, duplicate_bag
    this.keypos = 1; // 1-indexed position in tuple
    this.access = "protected"; // public, protected, private
    this.data = new Map(); // For set/ordered_set types

    // Parse options
    for (const option of options) {
      if (Type.isAtom(option)) {
        const value = option.value;
        if (["set", "ordered_set", "bag", "duplicate_bag"].includes(value)) {
          this.type = value;
        } else if (["public", "protected", "private"].includes(value)) {
          this.access = value;
        } else if (value === "named_table") {
          // Named tables use name as identifier
          this.isNamed = true;
        }
      } else if (Type.isTuple(option) && option.data.length === 2) {
        const key = option.data[0];
        const value = option.data[1];
        if (Type.isAtom(key) && key.value === "keypos" && Type.isInteger(value)) {
          this.keypos = Number(value.value);
        }
      }
    }

    // For bag and duplicate_bag, use array to store multiple values per key
    if (this.type === "bag" || this.type === "duplicate_bag") {
      this.data = new Map(); // key -> array of tuples
    }
  }

  getKey(tuple) {
    if (!Type.isTuple(tuple)) {
      return null;
    }

    const index = this.keypos - 1;
    if (index < 0 || index >= tuple.data.length) {
      return null;
    }

    return Type.encodeMapKey(tuple.data[index]);
  }

  insert(object) {
    const key = this.getKey(object);
    if (key === null) {
      return false;
    }

    if (this.type === "set" || this.type === "ordered_set") {
      this.data.set(key, object);
    } else if (this.type === "bag") {
      if (!this.data.has(key)) {
        this.data.set(key, []);
      }
      const existing = this.data.get(key);
      // For bag, don't insert if identical object exists
      const isDuplicate = existing.some((obj) =>
        Interpreter.isStrictlyEqual(obj, object),
      );
      if (!isDuplicate) {
        existing.push(object);
      }
    } else if (this.type === "duplicate_bag") {
      if (!this.data.has(key)) {
        this.data.set(key, []);
      }
      this.data.get(key).push(object);
    }

    return true;
  }

  lookup(key) {
    const encodedKey = Type.encodeMapKey(key);

    if (this.type === "set" || this.type === "ordered_set") {
      const value = this.data.get(encodedKey);
      return value ? [value] : [];
    } else {
      // bag or duplicate_bag
      return this.data.get(encodedKey) || [];
    }
  }

  delete(key) {
    const encodedKey = Type.encodeMapKey(key);
    this.data.delete(encodedKey);
  }

  deleteObject(object) {
    const key = this.getKey(object);
    if (key === null) {
      return;
    }

    if (this.type === "set" || this.type === "ordered_set") {
      const existing = this.data.get(key);
      if (existing && Interpreter.isStrictlyEqual(existing, object)) {
        this.data.delete(key);
      }
    } else {
      // bag or duplicate_bag
      const values = this.data.get(key);
      if (values) {
        const filtered = values.filter(
          (obj) => !Interpreter.isStrictlyEqual(obj, object),
        );
        if (filtered.length === 0) {
          this.data.delete(key);
        } else {
          this.data.set(key, filtered);
        }
      }
    }
  }

  member(key) {
    const encodedKey = Type.encodeMapKey(key);
    return this.data.has(encodedKey);
  }

  matchDelete(pattern) {
    // Simple pattern matching - just check for atom '_' wildcards
    // Full ETS match spec support would be more complex
    const toDelete = [];

    for (const [encodedKey, value] of this.data.entries()) {
      const objects = Array.isArray(value) ? value : [value];

      for (const obj of objects) {
        if (this.matchesPattern(obj, pattern)) {
          toDelete.push(encodedKey);
          break;
        }
      }
    }

    for (const key of toDelete) {
      this.data.delete(key);
    }

    return toDelete.length;
  }

  matchesPattern(object, pattern) {
    if (Type.isAtom(pattern) && pattern.value === "_") {
      return true;
    }

    if (Type.isTuple(object) && Type.isTuple(pattern)) {
      if (object.data.length !== pattern.data.length) {
        return false;
      }

      for (let i = 0; i < object.data.length; i++) {
        if (Type.isAtom(pattern.data[i]) && pattern.data[i].value === "_") {
          continue;
        }
        if (!Interpreter.isStrictlyEqual(object.data[i], pattern.data[i])) {
          return false;
        }
      }

      return true;
    }

    return Interpreter.isStrictlyEqual(object, pattern);
  }
}

function getTable(tableId) {
  // tableId can be a name (atom) or reference
  let table;

  if (Type.isAtom(tableId)) {
    table = etsTables.get(tableId.value);
  } else if (Type.isReference(tableId)) {
    // Search by reference
    for (const t of etsTables.values()) {
      if (
        Type.isReference(t.ref) &&
        Interpreter.isStrictlyEqual(t.ref, tableId)
      ) {
        table = t;
        break;
      }
    }
  }

  if (!table) {
    Interpreter.raiseArgumentError("argument error");
  }

  return table;
}

const Erlang_Ets = {
  // Start delete/2
  "delete/2": (tableId, key) => {
    const table = getTable(tableId);
    table.delete(key);
    return Type.boolean(true);
  },
  // End delete/2
  // Deps: []

  // Start delete_object/2
  "delete_object/2": (tableId, object) => {
    const table = getTable(tableId);
    table.deleteObject(object);
    return Type.boolean(true);
  },
  // End delete_object/2
  // Deps: []

  // Start info/2
  "info/2": (tableId, item) => {
    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    const table = getTable(tableId);

    switch (item.value) {
      case "name":
        return table.name;
      case "type":
        return Type.atom(table.type);
      case "keypos":
        return Type.integer(table.keypos);
      case "protection":
        return Type.atom(table.access);
      case "size":
        return Type.integer(table.data.size);
      case "named_table":
        return Type.boolean(table.isNamed || false);
      default:
        return Type.atom("undefined");
    }
  },
  // End info/2
  // Deps: []

  // Start insert/2
  "insert/2": (tableId, objectOrObjects) => {
    const table = getTable(tableId);

    if (Type.isList(objectOrObjects)) {
      // Insert multiple objects
      for (const object of objectOrObjects.data) {
        if (!table.insert(object)) {
          Interpreter.raiseArgumentError("argument error");
        }
      }
    } else {
      // Insert single object
      if (!table.insert(objectOrObjects)) {
        Interpreter.raiseArgumentError("argument error");
      }
    }

    return Type.boolean(true);
  },
  // End insert/2
  // Deps: []

  // Start insert_new/2
  "insert_new/2": (tableId, objectOrObjects) => {
    const table = getTable(tableId);
    const objects = Type.isList(objectOrObjects)
      ? objectOrObjects.data
      : [objectOrObjects];

    // Check if any key already exists
    for (const object of objects) {
      const key = table.getKey(object);
      if (key === null) {
        Interpreter.raiseArgumentError("argument error");
      }

      if (table.data.has(key)) {
        return Type.boolean(false);
      }
    }

    // All keys are new, insert them
    for (const object of objects) {
      table.insert(object);
    }

    return Type.boolean(true);
  },
  // End insert_new/2
  // Deps: []

  // Start lookup/2
  "lookup/2": (tableId, key) => {
    const table = getTable(tableId);
    const results = table.lookup(key);
    return Type.list(results);
  },
  // End lookup/2
  // Deps: []

  // Start lookup_element/3
  "lookup_element/3": (tableId, key, pos) => {
    if (!Type.isInteger(pos)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    const table = getTable(tableId);
    const results = table.lookup(key);

    if (results.length === 0) {
      Interpreter.raiseArgumentError("argument error");
    }

    const posNum = Number(pos.value);
    const index = posNum - 1;

    // For set/ordered_set, return single element
    if (table.type === "set" || table.type === "ordered_set") {
      const tuple = results[0];
      if (!Type.isTuple(tuple) || index < 0 || index >= tuple.data.length) {
        Interpreter.raiseArgumentError("argument error");
      }
      return tuple.data[index];
    } else {
      // For bag/duplicate_bag, return list of elements at position
      const elements = results.map((tuple) => {
        if (!Type.isTuple(tuple) || index < 0 || index >= tuple.data.length) {
          Interpreter.raiseArgumentError("argument error");
        }
        return tuple.data[index];
      });
      return Type.list(elements);
    }
  },
  // End lookup_element/3
  // Deps: []

  // Start match_delete/2
  "match_delete/2": (tableId, pattern) => {
    const table = getTable(tableId);
    const count = table.matchDelete(pattern);
    return Type.boolean(true);
  },
  // End match_delete/2
  // Deps: []

  // Start member/2
  "member/2": (tableId, key) => {
    const table = getTable(tableId);
    return Type.boolean(table.member(key));
  },
  // End member/2
  // Deps: []

  // Start new/2
  "new/2": (name, options) => {
    if (!Type.isAtom(name)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    const table = new EtsTable(name, options.data);

    // Store table
    if (table.isNamed) {
      etsTables.set(name.value, table);
      return name;
    } else {
      etsTables.set(table.ref.value, table);
      return table.ref;
    }
  },
  // End new/2
  // Deps: []

  // Start select/2
  "select/2": (tableId, matchSpec) => {
    const table = getTable(tableId);

    if (!Type.isList(matchSpec)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Simple implementation: just return all objects that match patterns
    // Full match spec support with guards and result transformations would be more complex
    const results = [];

    for (const [encodedKey, value] of table.data.entries()) {
      const objects = Array.isArray(value) ? value : [value];

      for (const obj of objects) {
        // Each match spec element is {pattern, guards, result}
        for (const spec of matchSpec.data) {
          if (Type.isTuple(spec) && spec.data.length >= 1) {
            const pattern = spec.data[0];
            if (table.matchesPattern(obj, pattern)) {
              // If no result transformation specified, return object as-is
              const result =
                spec.data.length >= 3 ? spec.data[2] : Type.list([obj]);
              results.push(obj);
              break;
            }
          }
        }
      }
    }

    return Type.list(results);
  },
  // End select/2
  // Deps: []

  // Start select/3
  "select/3": (tableId, matchSpec, limit) => {
    if (!Type.isInteger(limit)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    const table = getTable(tableId);

    if (!Type.isList(matchSpec)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    const limitNum = Number(limit.value);
    const results = [];
    let count = 0;

    for (const [encodedKey, value] of table.data.entries()) {
      if (count >= limitNum) {
        break;
      }

      const objects = Array.isArray(value) ? value : [value];

      for (const obj of objects) {
        if (count >= limitNum) {
          break;
        }

        for (const spec of matchSpec.data) {
          if (Type.isTuple(spec) && spec.data.length >= 1) {
            const pattern = spec.data[0];
            if (table.matchesPattern(obj, pattern)) {
              results.push(obj);
              count++;
              break;
            }
          }
        }
      }
    }

    // Return {results, continuation} or '$end_of_table'
    if (count < limitNum || table.data.size <= limitNum) {
      return Type.atom("$end_of_table");
    } else {
      // Simplified: just return results with end marker
      return Type.tuple([Type.list(results), Type.atom("$end_of_table")]);
    }
  },
  // End select/3
  // Deps: []

  // Start select_count/2
  "select_count/2": (tableId, matchSpec) => {
    const table = getTable(tableId);

    if (!Type.isList(matchSpec)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    let count = 0;

    for (const [encodedKey, value] of table.data.entries()) {
      const objects = Array.isArray(value) ? value : [value];

      for (const obj of objects) {
        for (const spec of matchSpec.data) {
          if (Type.isTuple(spec) && spec.data.length >= 1) {
            const pattern = spec.data[0];
            if (table.matchesPattern(obj, pattern)) {
              count++;
              break;
            }
          }
        }
      }
    }

    return Type.integer(count);
  },
  // End select_count/2
  // Deps: []

  // Start select_delete/2
  "select_delete/2": (tableId, matchSpec) => {
    const table = getTable(tableId);

    if (!Type.isList(matchSpec)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    const toDelete = [];

    for (const [encodedKey, value] of table.data.entries()) {
      const objects = Array.isArray(value) ? value : [value];

      for (const obj of objects) {
        for (const spec of matchSpec.data) {
          if (Type.isTuple(spec) && spec.data.length >= 1) {
            const pattern = spec.data[0];
            if (table.matchesPattern(obj, pattern)) {
              toDelete.push(encodedKey);
              break;
            }
          }
        }
      }
    }

    for (const key of toDelete) {
      table.data.delete(key);
    }

    return Type.integer(toDelete.length);
  },
  // End select_delete/2
  // Deps: []
};

export default Erlang_Ets;
