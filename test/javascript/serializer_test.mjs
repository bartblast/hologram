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

      describe("map", () => {
        it("top-level", () => {
          const term = Type.map([
            [Type.atom("x"), Type.integer(1)],
            [Type.bitstring("y"), Type.float(1.23)],
          ]);

          const expected =
            '[1,{"type":"map","data":[["__atom__:x","__integer__:1"],["__binary__:y","__float__:1.23"]]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.map([
              [Type.atom("x"), Type.integer(1)],
              [Type.bitstring("y"), Type.float(1.23)],
            ]),
            b: 2,
          };

          const expected =
            '[1,{"a":{"type":"map","data":[["__atom__:x","__integer__:1"],["__binary__:y","__float__:1.23"]]},"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("tuple", () => {
        it("top-level", () => {
          const term = Type.tuple([Type.integer(1), Type.float(1.23)]);

          const expected =
            '[1,{"type":"tuple","data":["__integer__:1","__float__:1.23"]}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: Type.tuple([Type.integer(1), Type.float(1.23)]),
            b: 2,
          };

          const expected =
            '[1,{"a":{"type":"tuple","data":["__integer__:1","__float__:1.23"]},"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });
    });

    describe("JS terms", () => {
      describe("array", () => {
        it("top-level", () => {
          const term = [123, Type.float(2.34), Type.bitstring([1, 0, 1, 0])];

          const expected =
            '[1,[123,"__float__:2.34",{"type":"bitstring","bits":[1,0,1,0]}]]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {
            a: [123, Type.float(2.34), Type.bitstring([1, 0, 1, 0])],
            b: 2,
          };

          const expected =
            '[1,{"a":[123,"__float__:2.34",{"type":"bitstring","bits":[1,0,1,0]}],"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

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

      describe("boolean", () => {
        it("top-level", () => {
          const term = true;
          const expected = "[1,true]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: true, b: 2};
          const expected = '[1,{"a":true,"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("float", () => {
        it("top-level", () => {
          const term = 2.34;
          const expected = "[1,2.34]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 1.23, b: 2};
          const expected = '[1,{"a":1.23,"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("integer", () => {
        it("top-level", () => {
          const term = 234;
          const expected = "[1,234]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 123, b: 2};
          const expected = '[1,{"a":123,"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("null", () => {
        it("top-level", () => {
          const term = null;
          const expected = "[1,null]";

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: null, b: 2};
          const expected = '[1,{"a":null,"b":2}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("object", () => {
        it("top-level", () => {
          const term = {a: 1, 'b"cd': 2.34};
          const expected = '[1,{"a":1,"b\\"cd":2.34}]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 1, b: {c: 3.45, 'd"ef': "xyz"}};
          const expected = '[1,{"a":1,"b":{"c":3.45,"d\\"ef":"xyz"}}]';

          assert.equal(serialize(term), expected);
        });
      });

      describe("string", () => {
        it("top-level", () => {
          const term = 'a"bc';
          const expected = '[1,"a\\"bc"]';

          assert.equal(serialize(term), expected);
        });

        it("nested", () => {
          const term = {a: 'x"yz', b: 2};
          const expected = '[1,{"a":"x\\"yz","b":2}]';

          assert.equal(serialize(term), expected);
        });
      });
    });
  });
});
