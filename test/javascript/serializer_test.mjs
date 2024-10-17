"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Serializer", () => {
  describe("serialize()", () => {
    const serialize = Serializer.serialize;

    describe("boxed terms", () => {
      it("atom", () => {
        const term = Type.atom('a"bc');
        const expected = '[1,"__atom__:a\\"bc"]';

        assert.equal(serialize(term), expected);
      });

      it("nested atom", () => {
        const term = {a: Type.atom('a"bc'), b: 2};
        const expected = '[1,{"a":"__atom__:a\\"bc","b":2}]';

        assert.equal(serialize(term), expected);
      });

      it("float", () => {
        const term = Type.float(1.23);
        const expected = '[1,"__float__:1.23"]';

        assert.equal(serialize(term), expected);
      });

      it("nested float", () => {
        const term = {a: Type.float(1.23), b: 2};
        const expected = '[1,{"a":"__float__:1.23","b":2}]';

        assert.equal(serialize(term), expected);
      });

      it("integer", () => {
        const term = Type.integer(123);
        const expected = '[1,"__integer__:123"]';

        assert.equal(serialize(term), expected);
      });

      it("nested integer", () => {
        const term = {a: Type.integer(123), b: 2};
        const expected = '[1,{"a":"__integer__:123","b":2}]';

        assert.equal(serialize(term), expected);
      });

      it("list", () => {
        const term = Type.list([Type.integer(1), Type.float(1.23)]);

        const expected =
          '[1,{"type":"list","data":["__integer__:1","__float__:1.23"],"isProper":true}]';

        assert.equal(serialize(term), expected);
      });

      it("nested list", () => {
        const term = {a: Type.list([Type.integer(1), Type.float(1.23)]), b: 2};

        const expected =
          '[1,{"a":{"type":"list","data":["__integer__:1","__float__:1.23"],"isProper":true},"b":2}]';

        assert.equal(serialize(term), expected);
      });
    });

    describe("JS terms", () => {
      it("JS BigInt", () => {
        const term = 123n;
        const expected = '[1,"__bigint__:123"]';

        assert.equal(serialize(term), expected);
      });

      it("nested JS BigInt", () => {
        const term = {a: 123n, b: 2};
        const expected = '[1,{"a":"__bigint__:123","b":2}]';

        assert.equal(serialize(term), expected);
      });
    });
  });
});
