"use strict";

import {
  assertError,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Hologram from "../../assets/js/hologram.mjs";

before(() => linkModules());
after(() => unlinkModules());

it("raiseCompileError()", () => {
  assertError(() => Hologram.raiseCompileError("abc"), "CompileError", "abc");
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
