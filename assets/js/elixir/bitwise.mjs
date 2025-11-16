"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

function assertIntegerArgs(funLabel, args) {
  if (args.every((arg) => Type.isInteger(arg))) {
    return;
  }

  const inspectedArgs = args.map((arg) => Interpreter.inspect(arg)).join(", ");
  const blame = `${funLabel}(${inspectedArgs})`;

  Interpreter.raiseArithmeticError(blame);
}

function applyBinaryOp(funLabel, left, right, op) {
  assertIntegerArgs(funLabel, [left, right]);

  const result = op(left.value, right.value);

  return Type.integer(result);
}

function applyUnaryOp(funLabel, value, op) {
  assertIntegerArgs(funLabel, [value]);

  return Type.integer(op(value.value));
}

function applyShiftOp(funLabel, left, right, direction) {
  assertIntegerArgs(funLabel, [left, right]);

  const shift = right.value;

  if (shift === 0n) {
    return Type.integer(left.value);
  }

  if (direction === "left") {
    return Type.integer(
      shift > 0n ? left.value << shift : left.value >> -shift,
    );
  }

  return Type.integer(
    shift > 0n ? left.value >> shift : left.value << -shift,
  );
}

const Elixir_Bitwise = {
  "bnot/1": function (value) {
    return applyUnaryOp("Bitwise.bnot", value, (operand) => ~operand);
  },

  "~~~/1": function (value) {
    return Elixir_Bitwise["bnot/1"](value);
  },

  "band/2": function (left, right) {
    return applyBinaryOp("Bitwise.band", left, right, (l, r) => l & r);
  },

  "&&&/2": function (left, right) {
    return Elixir_Bitwise["band/2"](left, right);
  },

  "bor/2": function (left, right) {
    return applyBinaryOp("Bitwise.bor", left, right, (l, r) => l | r);
  },

  "|||/2": function (left, right) {
    return Elixir_Bitwise["bor/2"](left, right);
  },

  "bxor/2": function (left, right) {
    return applyBinaryOp("Bitwise.bxor", left, right, (l, r) => l ^ r);
  },

  "^^^/2": function (left, right) {
    return Elixir_Bitwise["bxor/2"](left, right);
  },

  "bsl/2": function (left, right) {
    return applyShiftOp("Bitwise.bsl", left, right, "left");
  },

  "<<</2": function (left, right) {
    return Elixir_Bitwise["bsl/2"](left, right);
  },

  "bsr/2": function (left, right) {
    return applyShiftOp("Bitwise.bsr", left, right, "right");
  },

  ">>>/2": function (left, right) {
    return Elixir_Bitwise["bsr/2"](left, right);
  },
};

export default Elixir_Bitwise;
