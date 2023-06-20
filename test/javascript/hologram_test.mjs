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
