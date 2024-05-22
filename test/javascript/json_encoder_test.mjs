"use strict";

import {
  assert,
  assertBoxedError,
  contextFixture,
  linkModules,
  unlinkModules,
} from "./support/helpers.mjs";

import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import JsonEncoder from "../../assets/js/json_encoder.mjs";
import Type from "../../assets/js/type.mjs";

describe("JsonEncoder", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("encode()", () => {
    it("boxed anonymous function", () => {
      const term = Type.anonymousFunction(2, [], contextFixture());

      assertBoxedError(
        () => JsonEncoder.encode(term),
        "Hologram.RuntimeError",
        "can't JSON encode boxed anonymous functions",
      );
    });

    it("boxed atom", () => {
      const term = Type.atom('a"bc');
      const expected = '{"type":"atom","value":"a\\"bc"}';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    describe("boxed bitstring", () => {
      it("binary", () => {
        const term = Type.bitstring('a"bc');
        const expected = '"__binary__:a\\"bc"';

        assert.equal(JsonEncoder.encode(term), expected);
      });

      it("non-binary", () => {
        const term = Type.bitstring([1, 0, 1, 0]);

        const expected =
          '{"type":"bitstring","bits":{"0":1,"1":0,"2":1,"3":0}}';

        assert.equal(JsonEncoder.encode(term), expected);
      });
    });

    it("boxed float", () => {
      const term = Type.float(1.23);
      const expected = '{"type":"float","value":1.23}';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("boxed integer", () => {
      const term = Type.integer(123);
      const expected = '"__integer__:123"';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("boxed list", () => {
      const term = Type.list([Type.integer(1), Type.float(2.3)]);

      const expected =
        '{"type":"list","data":["__integer__:1",{"type":"float","value":2.3}]}';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("boxed map", () => {
      const term = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.bitstring("b"), Type.float(2.3)],
      ]);

      const expected =
        '{"type":"map","data":[[{"type":"atom","value":"a"},"__integer__:1"],["__binary__:b",{"type":"float","value":2.3}]]}';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    describe("boxed PID", () => {
      it("originating in client", () => {
        const term = Type.pid("my_node@my_host", [0, 11, 222], "client");

        assertBoxedError(
          () => JsonEncoder.encode(term),
          "Hologram.RuntimeError",
          "can't JSON encode PIDs originating in client",
        );
      });

      it("originating in server", () => {
        const term = Type.pid('my_node@my_"host', [0, 11, 222], "server");
        const expected = '{"type":"pid","segments":[0,11,222]}';

        assert.equal(JsonEncoder.encode(term), expected);
      });
    });

    describe("boxed port", () => {
      it("originating in client", () => {
        const term = Type.port("0.11", "client");

        assertBoxedError(
          () => JsonEncoder.encode(term),
          "Hologram.RuntimeError",
          "can't JSON encode ports originating in client",
        );
      });

      it("originating in server", () => {
        const term = Type.port("0.11", "server");
        const expected = '{"type":"port","value":"0.11"}';

        assert.equal(JsonEncoder.encode(term), expected);
      });
    });

    describe("boxed reference", () => {
      it("originating in client", () => {
        const term = Type.reference("0.1.2.3", "client");

        assertBoxedError(
          () => JsonEncoder.encode(term),
          "Hologram.RuntimeError",
          "can't JSON encode references originating in client",
        );
      });

      it("originating in server", () => {
        const term = Type.reference("0.1.2.3", "server");
        const expected = '{"type":"reference","value":"0.1.2.3"}';

        assert.equal(JsonEncoder.encode(term), expected);
      });
    });

    it("boxed tuple", () => {
      const term = Type.tuple([Type.integer(1), Type.float(2.3)]);

      const expected =
        '{"type":"tuple","data":["__integer__:1",{"type":"float","value":2.3}]}';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS array", () => {
      const term = [123, Type.float(2.34)];
      const expected = '[123,{"type":"float","value":2.34}]';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS BigInt", () => {
      const term = 123n;
      const expected = '"__integer__:123"';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS boolean", () => {
      const term = true;
      const expected = "true";

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS float", () => {
      const term = 1.23;
      const expected = "1.23";

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS integer", () => {
      const term = 123;
      const expected = "123";

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS null", () => {
      const term = null;
      const expected = "null";

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS object", () => {
      const term = {abc: 123, 'a"bc': 'a"bc'};
      const expected = '{"abc":123,"a\\"bc":"a\\"bc"}';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS string", () => {
      const term = 'a"bc';
      const expected = '"a\\"bc"';

      assert.equal(JsonEncoder.encode(term), expected);
    });

    it("JS undefined", () => {
      const term = undefined;
      const expected = "null";

      assert.equal(JsonEncoder.encode(term), expected);
    });
  });
});
