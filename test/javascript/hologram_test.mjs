"use strict";

import {
  assert,
  assertNotFrozen,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

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

describe("module()", () => {
  let Erlang, Erlang_Mymodule, Elixir_Aaa_Bbb_Ccc;

  before(() => {
    Erlang = class {};
    Hologram.Erlang = Erlang;

    Erlang_Mymodule = class {};
    Hologram.Erlang_Mymodule = Erlang_Mymodule;

    Elixir_Aaa_Bbb_Ccc = class {};
    Hologram.Elixir_Aaa_Bbb_Ccc = Elixir_Aaa_Bbb_Ccc;
  });

  after(() => {
    delete Hologram.Erlang;
    delete Hologram.Erlang_Mymodule;
    delete Hologram.Elixir_Aaa_Bbb_Ccc;
  });

  it("returns class for alias having lowercase starting letter", () => {
    const alias = Type.atom("mymodule");
    const result = Hologram.module(alias);

    assert.equal(result, Erlang_Mymodule);
  });

  it("returns class for alias not having lowercase starting letter", () => {
    const alias = Type.atom("Elixir.Aaa.Bbb.Ccc");
    const result = Hologram.module(alias);

    assert.equal(result, Elixir_Aaa_Bbb_Ccc);
  });

  it("returns class for :erlang alias", () => {
    const alias = Type.atom("erlang");
    const result = Hologram.module(alias);

    assert.equal(result, Erlang);
  });

  it("doesn't freeze the returned class", () => {
    const alias = Type.atom("erlang");
    const result = Hologram.module(alias);

    assertNotFrozen(result);
  });
});

it("raiseError()", () => {
  const expectedErrorData = Hologram.serialize({
    type: "map",
    data: {
      "atom(__exception__)": [Type.atom("__exception__"), Type.boolean(true)],
      "atom(message)": [Type.atom("message"), Type.bitstring("abc")],
      "atom(__struct__)": [Type.atom("__struct__"), Type.alias("Aaa.Bbb")],
    },
  });

  assert.throw(
    () => {
      Hologram.raiseError("Aaa.Bbb", "abc");
    },
    Error,
    `(HologramError) ${expectedErrorData}`
  );
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
