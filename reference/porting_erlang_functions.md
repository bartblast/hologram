# Porting Erlang/Elixir Functions to JavaScript for Hologram

This guide explains how to port Erlang `:lists` module functions (and other standard library functions) to JavaScript for the Hologram framework.

## Table of Contents

1. [Understanding Hologram's Architecture](#understanding-hologram-architecture)
2. [The Value Boxing System](#the-value-boxing-system)
3. [Step-by-Step Guide](#step-by-step-guide)
4. [Common Patterns](#common-patterns)
5. [Testing Guidelines](#testing-guidelines)
6. [Complete Example](#complete-example)

## Understanding Hologram Architecture

Hologram is an Elixir-to-JavaScript transpiler that runs Elixir code in the browser. To maintain Elixir/Erlang semantics, all values are "boxed" - wrapped in JavaScript objects that contain type information.

### Key Concepts

- **Value Boxing**: All values are objects with `type` and `value`/`data` properties
- **Type System**: The `Type` class provides methods to create and check boxed values
- **Interpreter**: Handles function calls, comparisons, and error raising
- **Erlang Semantics**: Must match OTP behavior exactly, including error messages

## The Value Boxing System

Every value in Hologram is represented as a JavaScript object:

```javascript
// Integer
{ type: "integer", value: 42n }  // BigInt for arbitrary precision

// Atom
{ type: "atom", value: "hello" }

// List (proper)
{ type: "list", data: [boxedElem1, boxedElem2] }

// Tuple
{ type: "tuple", data: [boxedElem1, boxedElem2] }

// Boolean (special atoms)
{ type: "boolean", value: true }  // Same as atom :true

// Float
{ type: "float", value: 3.14 }

// Anonymous Function
{
  type: "anonymousFunction",
  arity: 2,
  clauses: [...],
  context: {...}
}
```

### Type Helper Methods

```javascript
// Creating boxed values
Type.integer(42)           // Creates boxed integer
Type.atom("hello")         // Creates boxed atom
Type.list([...])          // Creates boxed list
Type.tuple([...])         // Creates boxed tuple
Type.boolean(true)        // Creates boxed boolean
Type.float(3.14)          // Creates boxed float

// Type checking
Type.isInteger(value)     // Check if integer
Type.isAtom(value)        // Check if atom
Type.isList(value)        // Check if list
Type.isTuple(value)       // Check if tuple
Type.isBoolean(value)     // Check if boolean
Type.isAnonymousFunction(value)  // Check if function
Type.isProperList(list)   // Check if list ends with nil (not improper)

// Special boolean checks
Type.isTrue(value)        // Check if exactly :true
Type.isFalse(value)       // Check if exactly :false
```

## Step-by-Step Guide

### Step 1: Understand the Erlang Function

Before implementing, understand the Erlang function's behavior:

```erlang
% Example: :lists.delete/2 in Erlang
:lists.delete(elem, list) -> list
```

**Research:**
1. Check Erlang documentation: https://www.erlang.org/doc/man/lists.html
2. Test in IEx to understand edge cases:
   ```elixir
   iex> :lists.delete(2, [1, 2, 3, 2])
   [1, 3, 2]  # Only deletes FIRST occurrence

   iex> :lists.delete(5, [1, 2, 3])
   [1, 2, 3]  # No match = returns original

   iex> :lists.delete(1, :not_a_list)
   ** (FunctionClauseError) ...  # Raises error
   ```

### Step 2: Find the Alphabetical Location

Functions **must** be in alphabetical order in `assets/js/erlang/lists.mjs`:

```javascript
// Find where your function fits alphabetically
"delete/2": (elem, list) => { ... },
// End delete/2
// Deps: []

// Your new function goes here if it starts with 'd' and comes after 'delete'
// Start droplast/1
"droplast/1": (list) => { ... },
// End droplast/1
// Deps: []

"duplicate/2": (elem, n) => { ... },
```

**Pattern:**
```javascript
// Start function_name/arity
"function_name/arity": (param1, param2) => {
  // implementation
},
// End function_name/arity
// Deps: [list, of, dependencies]
```

### Step 3: Implement the Function

Follow this structure:

```javascript
"delete/2": (elem, list) => {
  // 1. VALIDATE ARGUMENTS - check types and constraints
  if (!Type.isList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [elem, list]),
    );
  }

  // 2. CHECK PROPER LIST (no improper lists)
  if (!Type.isProperList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [elem, list]),
    );
  }

  // 3. IMPLEMENT LOGIC
  const result = [];
  let deleted = false;

  for (const item of list.data) {
    if (!deleted && Interpreter.isEqual(item, elem)) {
      deleted = true;  // Skip first match
    } else {
      result.push(item);
    }
  }

  // 4. RETURN BOXED VALUE
  return Type.list(result);
},
```

### Step 4: Handle Errors Correctly

**Three main error types:**

1. **FunctionClauseError** - Wrong argument types or pattern mismatch
   ```javascript
   Interpreter.raiseFunctionClauseError(
     Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [elem, list])
   );
   ```

2. **ArgumentError** - Invalid argument values (for key* functions)
   ```javascript
   Interpreter.raiseArgumentError(
     Interpreter.buildArgumentErrorMsg(2, "not an integer")
   );
   ```

3. **ErlangError** - Runtime errors (like length mismatch)
   ```javascript
   Interpreter.raiseErlangError(
     Interpreter.buildErlangErrorMsg(":lists_not_same_length")
   );
   ```

**When to use which error:**
- Most `:lists` functions use `FunctionClauseError`
- `key*` functions (keyfind, keysort, etc.) use `ArgumentError` for index validation
- Functions like `zip` use `ErlangError` for runtime conditions

## Common Patterns

### Pattern 1: Simple List Transformation

```javascript
"reverse/1": (list) => {
  if (!Type.isList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.reverse/1", [list]),
    );
  }

  if (!Type.isProperList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.reverse/1", [list]),
    );
  }

  return Type.list(list.data.slice().reverse());
},
```

### Pattern 2: Function with Predicate (Higher-Order Function)

```javascript
"filter/2": function (predicate, list) {
  // IMPORTANT: Use `function` keyword (not arrow) to access `arguments`
  if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.filter/2", arguments),
    );
  }

  if (!Type.isList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.filter/2", arguments),
    );
  }

  if (!Type.isProperList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.filter_1/3"),
    );
  }

  const result = [];
  for (const elem of list.data) {
    // Call the Elixir function
    const predicateResult = Interpreter.callAnonymousFunction(predicate, [elem]);

    if (Type.isTrue(predicateResult)) {
      result.push(elem);
    }
  }

  return Type.list(result);
},
```

### Pattern 3: Comparing Values

Always use `Interpreter.isEqual()` for equality checks and `Interpreter.compareTerms()` for ordering:

```javascript
// Equality check
if (Interpreter.isEqual(elem1, elem2)) {
  // Elements are equal
}

// Ordering (returns -1, 0, or 1)
const comparison = Interpreter.compareTerms(elem1, elem2);
if (comparison < 0) {
  // elem1 is less than elem2
}
```

### Pattern 4: Working with Tuples

```javascript
"keyfind/3": (value, index, tuples) => {
  // ... validation ...

  const indexNum = Number(index.value) - 1;  // Convert to 0-based

  for (const tuple of tuples.data) {
    if (Type.isTuple(tuple)) {
      // Check tuple has enough elements
      if (tuple.data.length >= index.value &&
          Interpreter.isEqual(tuple.data[indexNum], value)) {
        return tuple;
      }
    }
  }

  return Type.boolean(false);
},
```

### Pattern 5: Handling Integer/Float Mixed Math

```javascript
"sum/1": (list) => {
  // ... validation ...

  let sum = 0n;  // Start with BigInt
  let hasFloat = false;

  for (const elem of list.data) {
    if (Type.isInteger(elem)) {
      if (hasFloat) {
        sum += Number(elem.value);  // Add as Number if we have floats
      } else {
        sum += elem.value;  // Add as BigInt
      }
    } else if (Type.isFloat(elem)) {
      if (!hasFloat) {
        sum = Number(sum);  // Convert to Number on first float
        hasFloat = true;
      }
      sum += elem.value;
    }
  }

  return hasFloat ? Type.float(sum) : Type.integer(sum);
},
```

## Testing Guidelines

### Test File Location

Tests go in `/test/javascript/erlang/lists_test.mjs` in **alphabetical order**.

### Test Structure

```javascript
describe("delete/2", () => {
  const testedFun = Erlang_Lists["delete/2"];

  // 1. HAPPY PATH TESTS - Normal usage
  it("deletes first occurrence of element", () => {
    const list = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
      Type.integer(2),
    ]);
    const result = testedFun(Type.integer(2), list);

    assert.deepStrictEqual(
      result,
      Type.list([Type.integer(1), Type.integer(3), Type.integer(2)]),
    );
  });

  it("returns original list when element not found", () => {
    const list = Type.list([Type.integer(1), Type.integer(2)]);
    const result = testedFun(Type.integer(5), list);

    assert.deepStrictEqual(result, list);
  });

  // 2. EDGE CASES
  it("handles empty list", () => {
    const result = testedFun(Type.integer(1), Type.list([]));

    assert.deepStrictEqual(result, Type.list([]));
  });

  // 3. ERROR CASES
  it("raises FunctionClauseError if second argument is not a list", () => {
    assertBoxedError(
      () => testedFun(Type.integer(1), Type.atom("not_list")),
      "FunctionClauseError",
      Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [
        Type.integer(1),
        Type.atom("not_list"),
      ]),
    );
  });

  it("raises FunctionClauseError if list is improper", () => {
    assertBoxedError(
      () =>
        testedFun(
          Type.integer(1),
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ),
      "FunctionClauseError",
      Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [
        Type.integer(1),
        Type.improperList([Type.integer(1), Type.integer(2)]),
      ]),
    );
  });
});
```

### Test Coverage Checklist

For each function, test:
- ✅ Normal operation with typical inputs
- ✅ Empty list
- ✅ Single element list
- ✅ Edge cases specific to the function
- ✅ All error conditions
- ✅ Different data types (atoms, integers, tuples, etc.)

### Helper Assertions

```javascript
// Check boxed true
assertBoxedTrue(result);

// Check boxed false
assertBoxedFalse(result);

// Check boxed error
assertBoxedError(
  () => someFunction(...),
  "ErrorType",
  "expected error message"
);
```

## Complete Example

Let's implement `:lists.droplast/1` from scratch:

### 1. Research

```elixir
iex> :lists.droplast([1, 2, 3])
[1, 2]

iex> :lists.droplast([1])
[]

iex> :lists.droplast([])
** (FunctionClauseError) no function clause matching in :lists.droplast/1

iex> :lists.droplast(:not_a_list)
** (FunctionClauseError) no function clause matching in :lists.droplast/1
```

### 2. Implementation

```javascript
// In assets/js/erlang/lists.mjs, after "delete/2" and before "duplicate/2"

// Start droplast/1
"droplast/1": (list) => {
  if (!Type.isList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
    );
  }

  if (!Type.isProperList(list)) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
    );
  }

  if (list.data.length === 0) {
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
    );
  }

  return Type.list(list.data.slice(0, -1));
},
// End droplast/1
// Deps: []
```

### 3. Tests

```javascript
// In test/javascript/erlang/lists_test.mjs, after "delete/2" tests

describe("droplast/1", () => {
  const testedFun = Erlang_Lists["droplast/1"];

  it("drops last element from list", () => {
    const list = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);
    const result = testedFun(list);

    assert.deepStrictEqual(
      result,
      Type.list([Type.integer(1), Type.integer(2)]),
    );
  });

  it("returns empty list for single-element list", () => {
    const list = Type.list([Type.integer(1)]);
    const result = testedFun(list);

    assert.deepStrictEqual(result, Type.list([]));
  });

  it("raises FunctionClauseError for empty list", () => {
    assertBoxedError(
      () => testedFun(Type.list([])),
      "FunctionClauseError",
      Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [
        Type.list([]),
      ]),
    );
  });

  it("raises FunctionClauseError if argument is not a list", () => {
    assertBoxedError(
      () => testedFun(Type.atom("not_list")),
      "FunctionClauseError",
      Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [
        Type.atom("not_list"),
      ]),
    );
  });

  it("raises FunctionClauseError if list is improper", () => {
    assertBoxedError(
      () =>
        testedFun(Type.improperList([Type.integer(1), Type.integer(2)])),
      "FunctionClauseError",
      Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [
        Type.improperList([Type.integer(1), Type.integer(2)]),
      ]),
    );
  });
});
```

### 4. Run Tests

```bash
cd /home/user/hologram/assets
npm test -- ../test/javascript/erlang/lists_test.mjs
```

### 5. Commit

```bash
git add assets/js/erlang/lists.mjs test/javascript/erlang/lists_test.mjs
git commit -m "Port :lists.droplast/1 to JavaScript

- Drops the last element from a non-empty list
- Raises FunctionClauseError for empty lists and non-lists
- Includes comprehensive tests for all cases"
```

## Common Gotchas

### 1. Improper Lists Need 2+ Elements

```javascript
// ❌ WRONG - Will throw error
Type.improperList([Type.integer(1)])

// ✅ CORRECT - Needs at least 2 elements
Type.improperList([Type.integer(1), Type.integer(2)])
```

### 2. Use `function` Not Arrow Functions for `arguments`

```javascript
// ❌ WRONG - Arrow functions don't have `arguments`
"filter/2": (predicate, list) => {
  Interpreter.raiseFunctionClauseError(
    Interpreter.buildFunctionClauseErrorMsg(":lists.filter/2", arguments), // undefined!
  );
}

// ✅ CORRECT - Use function keyword
"filter/2": function (predicate, list) {
  Interpreter.raiseFunctionClauseError(
    Interpreter.buildFunctionClauseErrorMsg(":lists.filter/2", arguments),
  );
}
```

### 3. BigInt for Integers

```javascript
// ❌ WRONG - Regular number
Type.integer(42)

// ✅ CORRECT - BigInt literal
Type.integer(42n)

// Or convert from variable
const num = 42;
Type.integer(BigInt(num))
```

### 4. Convert BigInt Before JS Operations

```javascript
// ❌ WRONG - Can't use BigInt as array index
const index = someInteger.value;  // This is a BigInt
list.data[index]  // Error!

// ✅ CORRECT - Convert to Number
const index = Number(someInteger.value);
list.data[index]  // Works!
```

### 5. Remember 1-based vs 0-based Indexing

Erlang uses 1-based indexing, JavaScript uses 0-based:

```javascript
"nth/2": (n, list) => {
  // n is 1-based in Erlang
  const index = Number(n.value) - 1;  // Convert to 0-based for JS
  return list.data[index];
}
```

## Resources

- **Erlang Docs**: https://www.erlang.org/doc/man/lists.html
- **Hologram Type System**: `/assets/js/type.mjs`
- **Hologram Interpreter**: `/assets/js/interpreter.mjs`
- **Existing Functions**: `/assets/js/erlang/lists.mjs`
- **Test Examples**: `/test/javascript/erlang/lists_test.mjs`

## Getting Help

1. Look at similar existing functions in the codebase
2. Test the Erlang function in IEx to understand behavior
3. Check Erlang documentation for edge cases
4. Follow the established patterns consistently

Happy porting! 🚀
