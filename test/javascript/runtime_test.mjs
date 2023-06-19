"use strict";

import {assert, assertNotFrozen} from "../../assets/js/test_support.mjs";
import Runtime from "../../assets/js/runtime.mjs";
import Type from "../../assets/js/type.mjs";

describe("getClassByModuleAlias()", () => {
  let Erlang, Erlang_Mymodule, Elixir_Aaa_Bbb_Ccc;

  before(() => {
    globalThis.__hologram__ = {};
    globalThis.__hologram__.classRegistry = {};

    Erlang = class {};
    globalThis.__hologram__.classRegistry["Erlang"] = Erlang;
  });

  after(() => {
    delete globalThis.__hologram__;
  });

  it("encodes module alias having lowercase starting letter", () => {
    // setup
    const Erlang_Mymodule = class {};
    globalThis.__hologram__.classRegistry["Erlang_Mymodule"] = Erlang_Mymodule;

    const moduleAlias = Type.atom("mymodule");
    const result = Runtime.getClassByModuleAlias(moduleAlias);

    assert.equal(result, Erlang_Mymodule);
  });

  it("encodes module alias not having lowercase starting letter", () => {
    // setup
    const Elixir_Aaa_Bbb_Ccc = class {};
    globalThis.__hologram__.classRegistry["Elixir_Aaa_Bbb_Ccc"] =
      Elixir_Aaa_Bbb_Ccc;

    const moduleAlias = Type.atom("Elixir.Aaa.Bbb.Ccc");
    const result = Runtime.getClassByModuleAlias(moduleAlias);

    assert.equal(result, Elixir_Aaa_Bbb_Ccc);
  });

  it("encodes :erlang module alias", () => {
    const moduleAlias = Type.atom("erlang");
    const result = Runtime.getClassByModuleAlias(moduleAlias);

    assert.equal(result, Erlang);
  });

  it("doesn't freeze the returned class", () => {
    const moduleAlias = Type.atom("erlang");
    const result = Runtime.getClassByModuleAlias(moduleAlias);

    assertNotFrozen(result);
  });
});
