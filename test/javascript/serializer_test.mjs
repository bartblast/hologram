"use strict";

import {
  assert,
  contextFixture,
  linkModules,
  unlinkModules,
} from "./support/helpers.mjs";

import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

describe("Serializer", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("serialize()", () => {
    it("boxed anonymous function", () => {
      const term = Type.anonymousFunction(2, [], contextFixture());

      assert.throw(
        () => Serializer.serialize(term),
        HologramInterpreterError,
        "can't serialize boxed anonymous functions",
      );
    });

    it("boxed atom", () => {
      const term = Type.atom('a"bc');
      const expected = '{"type":"atom","value":"a\\"bc"}';

      assert.equal(Serializer.serialize(term), expected);
    });

    describe("boxed bitstring", () => {
      it("binary", () => {
        const term = Type.bitstring('a"bc');
        const expected = '"__binary__:a\\"bc"';

        assert.equal(Serializer.serialize(term), expected);
      });

      it("non-binary", () => {
        const term = Type.bitstring([1, 0, 1, 0]);

        const expected =
          '{"type":"bitstring","bits":{"0":1,"1":0,"2":1,"3":0}}';

        assert.equal(Serializer.serialize(term), expected);
      });
    });

    it("boxed float", () => {
      const term = Type.float(1.23);
      const expected = '{"type":"float","value":1.23}';

      assert.equal(Serializer.serialize(term), expected);
    });

    it("boxed integer", () => {
      const term = Type.integer(123);
      const expected = '"__integer__:123"';

      assert.equal(Serializer.serialize(term), expected);
    });

    it("boxed list", () => {
      const term = Type.list([Type.integer(1), Type.float(2.3)]);

      const expected =
        '{"type":"list",data:["__integer__:1",{"type":"float","value":2.3}]}';

      assert.equal(Serializer.serialize(term), expected);
    });

    it("boxed map", () => {
      const term = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.bitstring("b"), Type.float(2.3)],
      ]);

      const expected =
        '{"type":"map",data:[[{"type":"atom","value":"a"},"__integer__:1"],["__binary__:b",{"type":"float","value":2.3}]]}';

      assert.equal(Serializer.serialize(term), expected);
    });

    describe("boxed PID", () => {
      it("originating in client", () => {
        const term = Type.pid("my_node@my_host", [0, 11, 222], "client");

        assert.throw(
          () => Serializer.serialize(term),
          HologramInterpreterError,
          "can't serialize PIDs originating in client",
        );
      });

      it("originating in server", () => {
        const term = Type.pid('my_node@my_"host', [0, 11, 222], "server");

        const expected =
          '{"type":"pid","node":"my_node@my_\\"host","segments":[0,11,222]}';

        assert.equal(Serializer.serialize(term), expected);
      });
    });

    describe("boxed port", () => {
      it("originating in client", () => {
        const term = Type.port("0.11", "client");

        assert.throw(
          () => Serializer.serialize(term),
          HologramInterpreterError,
          "can't serialize ports originating in client",
        );
      });

      it("originating in server", () => {
        const term = Type.port("0.11", "server");
        const expected = '{"type":"port","value":"0.11"}';

        assert.equal(Serializer.serialize(term), expected);
      });
    });

    describe("boxed reference", () => {
      it("originating in client", () => {
        const term = Type.reference("0.1.2.3", "client");

        assert.throw(
          () => Serializer.serialize(term),
          HologramInterpreterError,
          "can't serialize references originating in client",
        );
      });

      it("originating in server", () => {
        const term = Type.reference("0.1.2.3", "server");
        const expected = '{"type":"reference","value":"0.1.2.3"}';

        assert.equal(Serializer.serialize(term), expected);
      });
    });

    it("boxed tuple", () => {
      const term = Type.tuple([Type.integer(1), Type.float(2.3)]);

      const expected =
        '{"type":"tuple",data:["__integer__:1",{"type":"float","value":2.3}]}';

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS array", () => {
      const term = [123, "abc"];
      const expected = '[123,"abc"]';

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS BigInt", () => {
      const term = 123n;
      const expected = '"__integer__:123"';

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS boolean", () => {
      const term = true;
      const expected = "true";

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS float", () => {
      const term = 1.23;
      const expected = "1.23";

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS integer", () => {
      const term = 123;
      const expected = "123";

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS null", () => {
      const term = null;
      const expected = "null";

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS object", () => {
      const term = {abc: 123, 'a"bc': 'a"bc'};
      const expected = '{"abc":123,"a\\"bc":"a\\"bc"}';

      assert.equal(Serializer.serialize(term), expected);
    });

    it("JS string", () => {
      const term = 'a"bc';
      const expected = '"a\\"bc"';

      assert.equal(Serializer.serialize(term), expected);
    });
  });
});
