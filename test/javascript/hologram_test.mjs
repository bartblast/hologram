"use strict";

import {assert, assertNotFrozen} from "../../assets/js/test_support.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Type from "../../assets/js/type.mjs";

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
