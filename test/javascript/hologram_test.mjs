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

describe("cloneVars()", () => {
  it("clones vars recursively (deep clone) and removes __snapshot__ property", () => {
    const nested = {c: 3, d: 4};
    const vars = {a: 1, b: nested, __snapshot__: "dummy"};
    const expected = {a: 1, b: nested};
    const result = Hologram.cloneVars(vars);

    assert.deepStrictEqual(result, expected);
    assert.notEqual(result.b, nested);
  });
});

describe("deserialize()", () => {
  it("deserializes number from JSON", () => {
    const result = Hologram.deserialize("123");
    assert.equal(result, 123);
  });

  it("deserializes string from JSON", () => {
    const result = Hologram.deserialize('"abc"');
    assert.equal(result, "abc");
  });

  it("deserializes non-negative bigint from JSON", () => {
    const result = Hologram.deserialize('"__bigint__:123"');
    assert.equal(result, 123n);
  });

  it("deserializes negative bigint from JSON", () => {
    const result = Hologram.deserialize('"__bigint__:-123"');
    assert.equal(result, -123n);
  });

  it("deserializes non-nested object from JSON", () => {
    const result = Hologram.deserialize('{"a":1,"b":2}');
    assert.deepStrictEqual(result, {a: 1, b: 2});
  });

  it("deserializes nested object from JSON", () => {
    const result = Hologram.deserialize('{"a":1,"b":2,"c":{"d":3,"e":4}}');
    const expected = {a: 1, b: 2, c: {d: 3, e: 4}};

    assert.deepStrictEqual(result, expected);
  });
});

describe("inspect()", () => {
  it("proxies to Kernel.inspect/2", () => {
    const result = Hologram.inspect(Type.integer(123));
    assert.equal(result, "123");
  });
});

describe("inspectModuleName()", () => {
  it("inspects Elixir module name", () => {
    const result = Hologram.inspectModuleName("Elixir_Aaa_Bbb");
    assert.deepStrictEqual(result, "Aaa.Bbb");
  });

  it("inspects 'Erlang' module name", () => {
    const result = Hologram.inspectModuleName("Erlang");
    assert.deepStrictEqual(result, ":erlang");
  });

  it("inspects Erlang standard lib module name", () => {
    const result = Hologram.inspectModuleName("Erlang_uri_string");
    assert.deepStrictEqual(result, ":uri_string");
  });
});

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
    "abc"
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
