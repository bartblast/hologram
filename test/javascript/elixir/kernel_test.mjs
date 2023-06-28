"use strict";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Elixir_Kernel from "../../../assets/js/elixir/kernel.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("inspect()", () => {
  it("inspects boxed atom not being boolean or nil", () => {
    const result = Elixir_Kernel.inspect(Type.atom("abc"));
    assert.equal(result, ":abc");
  });

  it("inspects boxed atom being boolean", () => {
    const result = Elixir_Kernel.inspect(Type.boolean(true));
    assert.equal(result, "true");
  });

  it("inspects boxed atom being nil", () => {
    const result = Elixir_Kernel.inspect(Type.nil());
    assert.equal(result, "nil");
  });

  it("inspects boxed float, which can't be converted to integer", () => {
    const result = Elixir_Kernel.inspect(Type.float(123.45));
    assert.equal(result, "123.45");
  });

  it("inspects boxed float, which can be converted to integer", () => {
    const result = Elixir_Kernel.inspect(Type.float(123.0));
    assert.equal(result, "123.0");
  });

  it("inspects boxed integer", () => {
    const result = Elixir_Kernel.inspect(Type.integer(123));
    assert.equal(result, "123");
  });

  it("inspects boxed list", () => {
    const term = Type.list([Type.integer(123), Type.atom("abc")]);
    const result = Elixir_Kernel.inspect(term);

    assert.equal(result, "[123, :abc]");
  });

  it("inspects boxed tuple", () => {
    const term = Type.tuple([Type.integer(123), Type.atom("abc")]);
    const result = Elixir_Kernel.inspect(term);

    assert.equal(result, "{123, :abc}");
  });

  it("inspects other boxed types", () => {
    const segment = Type.bitstringSegment(Type.integer(170), {type: "integer"});
    const term = Type.bitstring([segment]);
    const result = Elixir_Kernel.inspect(term);

    assert.equal(
      result,
      '{"type":"bitstring","bits":{"0":1,"1":0,"2":1,"3":0,"4":1,"5":0,"6":1,"7":0}}'
    );
  });

  // TODO: test other boxed types
});
