"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Erlang array is represented as a tuple {array, Size, Max, Default, Elements}
// For simplicity, we use a sparse representation with a Map

function isArray(term) {
  if (!Type.isTuple(term) || term.data.length < 5) {
    return false;
  }
  const marker = term.data[0];
  return Type.isAtom(marker) && marker.value === "array";
}

function createArray(size = 0, defaultValue = Type.atom("undefined"), elements = {}) {
  return Type.tuple([
    Type.atom("array"),
    Type.integer(size),
    Type.integer(10), // Max (growth parameter)
    defaultValue,
    Type.map(Object.entries(elements).map(([k, v]) => [Type.integer(parseInt(k)), v]))
  ]);
}

function getArraySize(array) {
  if (!isArray(array)) {
    Interpreter.raiseArgumentError("argument error");
  }
  return Number(array.data[1].value);
}

function getArrayDefault(array) {
  if (!isArray(array)) {
    Interpreter.raiseArgumentError("argument error");
  }
  return array.data[3];
}

function getArrayElements(array) {
  if (!isArray(array)) {
    Interpreter.raiseArgumentError("argument error");
  }
  return array.data[4].data;
}

const Erlang_Array = {
  // Start new/0
  "new/0": () => {
    return createArray(0);
  },
  // End new/0
  // Deps: []

  // Start new/1
  "new/1": (sizeOrOptions) => {
    if (Type.isInteger(sizeOrOptions)) {
      // Size specified
      return createArray(Number(sizeOrOptions.value));
    } else if (Type.isList(sizeOrOptions)) {
      // Options list
      let size = 0;
      let defaultValue = Type.atom("undefined");
      let fixed = false;

      for (const option of sizeOrOptions.data) {
        if (Type.isTuple(option) && option.data.length === 2) {
          const key = option.data[0];
          const value = option.data[1];

          if (Type.isAtom(key)) {
            if (key.value === "size" && Type.isInteger(value)) {
              size = Number(value.value);
            } else if (key.value === "default") {
              defaultValue = value;
            } else if (key.value === "fixed" && Type.isBoolean(value)) {
              fixed = value.value;
            }
          }
        }
      }

      return createArray(size, defaultValue);
    } else {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End new/1
  // Deps: []

  // Start new/2
  "new/2": (size, options) => {
    if (!Type.isInteger(size)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    let defaultValue = Type.atom("undefined");

    for (const option of options.data) {
      if (Type.isTuple(option) && option.data.length === 2) {
        const key = option.data[0];
        const value = option.data[1];

        if (Type.isAtom(key) && key.value === "default") {
          defaultValue = value;
        }
      }
    }

    return createArray(Number(size.value), defaultValue);
  },
  // End new/2
  // Deps: []

  // Start set/3
  "set/3": (index, value, array) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!isArray(array)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an array"),
      );
    }

    const indexNum = Number(index.value);
    const size = getArraySize(array);
    const defaultValue = getArrayDefault(array);
    const elements = getArrayElements(array);

    if (indexNum < 0) {
      Interpreter.raiseArgumentError("argument error");
    }

    // Expand array if needed
    const newSize = Math.max(size, indexNum + 1);
    const newElements = {...elements};
    const encodedKey = Type.encodeMapKey(index);
    newElements[encodedKey] = [index, value];

    return Type.tuple([
      Type.atom("array"),
      Type.integer(newSize),
      Type.integer(10),
      defaultValue,
      Type.map(Object.values(newElements))
    ]);
  },
  // End set/3
  // Deps: []

  // Start get/2
  "get/2": (index, array) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!isArray(array)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an array"),
      );
    }

    const indexNum = Number(index.value);
    const size = getArraySize(array);
    const defaultValue = getArrayDefault(array);
    const elements = getArrayElements(array);

    if (indexNum < 0 || indexNum >= size) {
      Interpreter.raiseArgumentError("argument error");
    }

    const encodedKey = Type.encodeMapKey(index);
    if (elements[encodedKey]) {
      return elements[encodedKey][1];
    }

    return defaultValue;
  },
  // End get/2
  // Deps: []

  // Start size/1
  "size/1": (array) => {
    if (!isArray(array)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an array"),
      );
    }

    return array.data[1]; // Size is the second element
  },
  // End size/1
  // Deps: []

  // Start default/1
  "default/1": (array) => {
    if (!isArray(array)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an array"),
      );
    }

    return array.data[3]; // Default value is the fourth element
  },
  // End default/1
  // Deps: []

  // Start to_list/1
  "to_list/1": (array) => {
    if (!isArray(array)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an array"),
      );
    }

    const size = getArraySize(array);
    const defaultValue = getArrayDefault(array);
    const elements = getArrayElements(array);

    const list = [];
    for (let i = 0; i < size; i++) {
      const index = Type.integer(i);
      const encodedKey = Type.encodeMapKey(index);

      if (elements[encodedKey]) {
        list.push(elements[encodedKey][1]);
      } else {
        list.push(defaultValue);
      }
    }

    return Type.list(list);
  },
  // End to_list/1
  // Deps: []

  // Start from_list/1
  "from_list/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    const elements = {};
    list.data.forEach((value, i) => {
      const index = Type.integer(i);
      const encodedKey = Type.encodeMapKey(index);
      elements[encodedKey] = [index, value];
    });

    return createArray(list.data.length, Type.atom("undefined"), elements);
  },
  // End from_list/1
  // Deps: []

  // Start from_list/2
  "from_list/2": (list, defaultValue) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    const elements = {};
    list.data.forEach((value, i) => {
      const index = Type.integer(i);
      const encodedKey = Type.encodeMapKey(index);
      elements[encodedKey] = [index, value];
    });

    return createArray(list.data.length, defaultValue, elements);
  },
  // End from_list/2
  // Deps: []
};

export default Erlang_Array;
