"use strict";

import {
  assert,
  assertError,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

it("raiseArgumentError()", () => {
  assertError(() => Hologram.raiseArgumentError("abc"), "ArgumentError", "abc");
});

it("raiseBadMapError()", () => {
  assertError(() => Hologram.raiseBadMapError("abc"), "BadMapError", "abc");
});

it("raiseCompileError()", () => {
  assertError(() => Hologram.raiseCompileError("abc"), "CompileError", "abc");
});

it("raiseError()", () => {
  assertError(() => Hologram.raiseError("Aaa.Bbb", "abc"), "Aaa.Bbb", "abc");
});

it("raiseInterpreterError()", () => {
  assertError(
    () => Hologram.raiseInterpreterError("abc"),
    "Hologram.InterpreterError",
    "abc",
  );
});

it("raiseKeyError()", () => {
  assertError(() => Hologram.raiseKeyError("abc"), "KeyError", "abc");
});
