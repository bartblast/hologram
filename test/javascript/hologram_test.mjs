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

it("module()", () => {
  assert.equal(Hologram.module("maps"), Erlang_maps);
});

describe("moduleName()", () => {
  it("returns module name for alias having lowercase starting letter", () => {
    const alias = Type.atom("aaa_bbb");
    const result = Hologram.moduleName(alias);

    assert.equal(result, "Erlang_aaa_bbb");
  });

  it("returns module name for alias not having lowercase starting letter", () => {
    const alias = Type.atom("Elixir.Aaa.Bbb");
    const result = Hologram.moduleName(alias);

    assert.equal(result, "Elixir_Aaa_Bbb");
  });

  it("returns module name for :erlang alias", () => {
    const alias = Type.atom("erlang");
    const result = Hologram.moduleName(alias);

    assert.equal(result, "Erlang");
  });

  it("works with string arguments", () => {
    const result = Hologram.moduleName("Elixir.Aaa.Bbb");
    assert.equal(result, "Elixir_Aaa_Bbb");
  });
});

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

describe("serialize()", () => {
  it("serializes number to JSON", () => {
    assert.equal(Hologram.serialize(123), "123");
  });

  it("serializes string to JSON", () => {
    assert.equal(Hologram.serialize("abc"), '"abc"');
  });

  it("serializes non-negative bigint to JSON", () => {
    assert.equal(Hologram.serialize(123n), '"__bigint__:123"');
  });

  it("serializes negative bigint to JSON", () => {
    assert.equal(Hologram.serialize(-123n), '"__bigint__:-123"');
  });

  it("serializes non-nested object to JSON", () => {
    assert.equal(Hologram.serialize({a: 1, b: 2}), '{"a":1,"b":2}');
  });

  it("serializes nested object to JSON", () => {
    const term = {a: 1, b: 2, c: {d: 3, e: 4}};
    const expected = '{"a":1,"b":2,"c":{"d":3,"e":4}}';

    assert.equal(Hologram.serialize(term), expected);
  });
});
