"use strict";

import {assert, defineRuntimeGlobals, sinon} from "../support/helpers.mjs";

import CallStack from "../../../assets/js/erts/call_stack.mjs";
import HologramBoxedError from "../../../assets/js/errors/boxed_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

const myModuleFrame = {
  module: "MyModule",
  function: "my_fun",
  arityOrArgs: 1,
  file: "lib/my_module.ex",
  line: 11,
  errorInfo: null,
};

describe("HologramBoxedError", () => {
  beforeEach(() => {
    CallStack.reset();
  });

  describe("error kind (default)", () => {
    it("defaults the kind to :error", () => {
      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.deepStrictEqual(error.kind, Type.atom("error"));
    });

    it("sets value and struct to the given exception struct", () => {
      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.deepStrictEqual(error.value, struct);
      assert.deepStrictEqual(error.struct, struct);
    });

    it("normalizes a bare reason, keeping the raw reason in value", () => {
      const reason = Type.atom("badarg");
      const error = new HologramBoxedError(reason);

      // value carries the raw reason; struct is its normalized exception form.
      assert.deepStrictEqual(error.value, reason);
      assert.isTrue(Type.isStruct(error.struct));
    });

    it("captures a call stack snapshot at construction time", () => {
      const struct = Type.errorStruct("MyType", "my message");

      CallStack.push(myModuleFrame);
      const error = new HologramBoxedError(struct);
      CallStack.pop();

      assert.deepStrictEqual(error.stacktrace, [myModuleFrame]);
    });

    it("renders the message from the exception type and message", () => {
      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.equal(error.message, "(MyType) my message");
    });

    it("renders the message from the blamed struct, which struct doesn't mirror", () => {
      globalThis.Elixir_MyBlamedType = {
        "blame/2": (_struct, stacktrace) =>
          Type.tuple([
            Type.errorStruct("MyBlamedType", "my blamed message"),
            stacktrace,
          ]),
      };

      const struct = Type.errorStruct("MyBlamedType", "my message");
      const error = new HologramBoxedError(struct);

      delete globalThis.Elixir_MyBlamedType;

      assert.deepStrictEqual(error.struct, struct);

      assert.deepStrictEqual(
        error.blamedStruct,
        Type.errorStruct("MyBlamedType", "my blamed message"),
      );

      assert.equal(error.message, "(MyBlamedType) my blamed message");
    });

    // Extra enumerable own-properties on a thrown Error blank out the message that
    // the browser's uncaught-error reporting surfaces, so the internal carriers
    // must stay non-enumerable.
    it("defines kind, value, stacktrace, struct and blamedStruct as non-enumerable", () => {
      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.equal(
        Object.getOwnPropertyDescriptor(error, "kind").enumerable,
        false,
      );

      assert.equal(
        Object.getOwnPropertyDescriptor(error, "value").enumerable,
        false,
      );

      assert.equal(
        Object.getOwnPropertyDescriptor(error, "stacktrace").enumerable,
        false,
      );

      assert.equal(
        Object.getOwnPropertyDescriptor(error, "struct").enumerable,
        false,
      );

      assert.equal(
        Object.getOwnPropertyDescriptor(error, "blamedStruct").enumerable,
        false,
      );
    });

    it("can throw and catch", () => {
      const struct = Type.errorStruct("MyType", "my message");

      try {
        throw new HologramBoxedError(struct);
      } catch (error) {
        assert.instanceOf(error, HologramBoxedError);
        assert.deepStrictEqual(error.struct, struct);
      }
    });
  });

  describe("error raised while another error derives", () => {
    let normalizeErrorStub;

    // Mirrors a derivation that raises - a port missing from the bundle, a formatter failing on
    // the term it is given - by raising a boxed error out of the first thing derivation calls.
    const deriveByRaising = (reason) => {
      normalizeErrorStub = sinon
        .stub(Interpreter, "normalizeError")
        .callsFake(() => {
          throw new HologramBoxedError(reason);
        });
    };

    afterEach(() => {
      normalizeErrorStub?.restore();
      normalizeErrorStub = null;
    });

    it("carries the raised error out instead of exhausting the stack", () => {
      const reason = Type.errorStruct("MyRaisedType", "my raised message");
      deriveByRaising(reason);

      let caught;

      try {
        new HologramBoxedError(Type.errorStruct("MyType", "my message"));
      } catch (error) {
        caught = error;
      }

      assert.instanceOf(caught, HologramBoxedError);
      assert.deepStrictEqual(caught.value, reason);
    });

    it("leaves the raised error in the raw form it arrived in", () => {
      const reason = Type.errorStruct("MyRaisedType", "my raised message");
      deriveByRaising(reason);

      let caught;

      try {
        new HologramBoxedError(Type.errorStruct("MyType", "my message"));
      } catch (error) {
        caught = error;
      }

      assert.deepStrictEqual(caught.struct, reason);
      assert.deepStrictEqual(caught.blamedStruct, reason);

      assert.equal(
        caught.message,
        '(MyRaisedType) %{__exception__: true, message: "my raised message", __struct__: MyRaisedType}',
      );
    });

    it("names no struct for a bare reason raised while deriving", () => {
      deriveByRaising(Type.atom("badarg"));

      let caught;

      try {
        new HologramBoxedError(Type.errorStruct("MyType", "my message"));
      } catch (error) {
        caught = error;
      }

      assert.isNull(caught.struct);
      assert.isNull(caught.blamedStruct);
      assert.equal(caught.message, "(error) :badarg");
    });

    it("derives the next error normally once the raise has unwound", () => {
      deriveByRaising(Type.atom("badarg"));

      try {
        new HologramBoxedError(Type.errorStruct("MyType", "my message"));
      } catch {
        // The raise is the point - what matters is the state it leaves behind.
      }

      normalizeErrorStub.restore();
      normalizeErrorStub = null;

      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.deepStrictEqual(error.struct, struct);
      assert.equal(error.message, "(MyType) my message");
    });
  });

  describe("failure in the derivation itself", () => {
    let normalizeErrorStub;

    // Mirrors the derivation machinery faulting rather than raising the Elixir way - a helper
    // reading a shape it doesn't handle, say - which arrives as a plain JavaScript error.
    const deriveByFaulting = () => {
      normalizeErrorStub = sinon
        .stub(Interpreter, "normalizeError")
        .callsFake(() => {
          throw new TypeError("my fault");
        });
    };

    afterEach(() => {
      normalizeErrorStub?.restore();
      normalizeErrorStub = null;
    });

    it("keeps the error the caller raised", () => {
      deriveByFaulting();

      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.deepStrictEqual(error.value, struct);
      assert.deepStrictEqual(error.struct, struct);
    });

    it("names the fault alongside the raw form", () => {
      deriveByFaulting();

      const error = new HologramBoxedError(
        Type.errorStruct("MyType", "my message"),
      );

      assert.equal(
        error.message,
        '(MyType) %{__exception__: true, message: "my message", __struct__: MyType} ' +
          "(message derivation failed: my fault)",
      );
    });

    it("derives the next error normally", () => {
      deriveByFaulting();

      new HologramBoxedError(Type.errorStruct("MyType", "my message"));

      normalizeErrorStub.restore();
      normalizeErrorStub = null;

      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.equal(error.message, "(MyType) my message");
    });
  });

  describe("throw kind", () => {
    it("sets kind and value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("throw"));

      assert.deepStrictEqual(error.kind, Type.atom("throw"));
      assert.deepStrictEqual(error.value, value);
    });

    it("captures a call stack snapshot at construction time", () => {
      CallStack.push(myModuleFrame);
      const error = new HologramBoxedError(
        Type.integer(42),
        Type.atom("throw"),
      );
      CallStack.pop();

      assert.deepStrictEqual(error.stacktrace, [myModuleFrame]);
    });

    it("renders the message from the inspected value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("throw"));

      assert.equal(error.message, "(throw) 42");
    });
  });

  describe("exit kind", () => {
    it("sets kind and value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("exit"));

      assert.deepStrictEqual(error.kind, Type.atom("exit"));
      assert.deepStrictEqual(error.value, value);
    });

    it("renders the message from the inspected value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("exit"));

      assert.equal(error.message, "(exit) 42");
    });
  });
});
