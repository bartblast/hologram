"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe.only("Serializer", () => {
  describe("serialize()", () => {
    const serialize = Serializer.serialize;

    describe("boxed terms", () => {
      describe("atom", () => {
        it("top-level", () => {
          const term = Type.atom('a"bc');
          const expected = '[1,"__atom__:a\\"bc"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.atom('a"bc'), b: 2};
          const expected = '[1,{"a":"__atom__:a\\"bc","b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("bitstring", () => {
        describe("binary", () => {
          it("top-level", () => {
            const term = Type.bitstring('a"bc');
            const expected = '[1,"__binary__:a\\"bc"]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.bitstring('a"bc'), b: 2};
            const expected = '[1,{"a":"__binary__:a\\"bc","b":2}]';

            assert.equal(serialize(term), expected);
          });
        });

        describe("non-binary", () => {
          it("top-level", () => {
            const term = Type.bitstring([1, 0, 1, 0]);
            const expected = '[1,{"type":"bitstring","bits":[1,0,1,0]}]';

            assert.equal(serialize(term), expected);
          });

          it("nested", () => {
            const term = {a: Type.bitstring([1, 0, 1, 0]), b: 2};
            const expected =
              '[1,{"a":{"type":"bitstring","bits":[1,0,1,0]},"b":2}]';

            assert.equal(serialize(term), expected);
          });
        });
      });

      describe("float", () => {
        it("top-level", () => {
          const term = Type.float(1.23);
          const expected = '[1,"__float__:1.23"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.float(1.23), b: 2};
          const expected = '[1,{"a":"__float__:1.23","b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("integer", () => {
        it("top-level", () => {
          const term = Type.integer(123);
          const expected = '[1,"__integer__:123"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: Type.integer(123), b: 2};
          const expected = '[1,{"a":"__integer__:123","b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("list", () => {
        it("top-level", () => {
          const term = Type.list([Type.integer(1), Type.float(1.23)]);

          const expected =
            '[1,{"type":"list","data":["__integer__:1","__float__:1.23"],"isProper":true}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.list([Type.integer(1), Type.float(1.23)]),
            b: 2,
          };

          const expected =
            '[1,{"a":{"type":"list","data":["__integer__:1","__float__:1.23"],"isProper":true},"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });
    });

    describe("JS terms", () => {
      describe("BigInt", () => {
        it("top-level", () => {
          const term = 123n;
          const expected = '[1,"__bigint__:123"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 123n, b: 2};
          const expected = '[1,{"a":"__bigint__:123","b":2}]';

          assert.equal(serialize(term), expected);
        });
      });
    });
  });
});
