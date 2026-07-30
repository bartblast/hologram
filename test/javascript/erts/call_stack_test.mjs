"use strict";

import {assert} from "../support/helpers.mjs";

import CallStack from "../../../assets/js/erts/call_stack.mjs";
import Type from "../../../assets/js/type.mjs";

const enumFrame = {
  module: "Enum",
  function: "map",
  arityOrArgs: 2,
  file: "lib/enum.ex",
  line: 1_696,
  errorInfo: null,
};

const myModuleFrame = {
  module: "MyModule",
  function: "my_fun",
  arityOrArgs: 1,
  file: "lib/my_module.ex",
  line: 11,
  errorInfo: null,
};

describe("CallStack", () => {
  beforeEach(() => {
    CallStack.reset();
  });

  describe("boxFrame()", () => {
    it("converts an Elixir module frame", () => {
      const result = CallStack.boxFrame(myModuleFrame);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.alias("MyModule"),
          Type.atom("my_fun"),
          Type.integer(1),
          Type.list([
            Type.tuple([Type.atom("file"), Type.charlist("lib/my_module.ex")]),
            Type.tuple([Type.atom("line"), Type.integer(11)]),
          ]),
        ]),
      );
    });

    it("converts an Erlang module frame", () => {
      const frame = {...enumFrame, module: "maps", function: "get"};

      const result = CallStack.boxFrame(frame);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.atom("maps"),
          Type.atom("get"),
          Type.integer(2),
          Type.list([
            Type.tuple([Type.atom("file"), Type.charlist("lib/enum.ex")]),
            Type.tuple([Type.atom("line"), Type.integer(1_696)]),
          ]),
        ]),
      );
    });

    it("passes boxed args through in place of arity", () => {
      const args = Type.list([Type.integer(1), Type.integer(2)]);
      const frame = {...myModuleFrame, arityOrArgs: args};

      const result = CallStack.boxFrame(frame);

      assert.deepStrictEqual(result.data[2], args);
    });

    it("appends error_info to the location", () => {
      const errorInfo = Type.map([
        [Type.atom("module"), Type.atom("my_format_module")],
      ]);

      const frame = {...myModuleFrame, errorInfo};

      const result = CallStack.boxFrame(frame);

      assert.deepStrictEqual(
        result.data[3],
        Type.list([
          Type.tuple([Type.atom("file"), Type.charlist("lib/my_module.ex")]),
          Type.tuple([Type.atom("line"), Type.integer(11)]),
          Type.tuple([Type.atom("error_info"), errorInfo]),
        ]),
      );
    });

    it("omits a null file from the location", () => {
      const frame = {...myModuleFrame, file: null};

      const result = CallStack.boxFrame(frame);

      assert.deepStrictEqual(
        result.data[3],
        Type.list([Type.tuple([Type.atom("line"), Type.integer(11)])]),
      );
    });

    it("omits a null line from the location", () => {
      const frame = {...myModuleFrame, line: null};

      const result = CallStack.boxFrame(frame);

      assert.deepStrictEqual(
        result.data[3],
        Type.list([
          Type.tuple([Type.atom("file"), Type.charlist("lib/my_module.ex")]),
        ]),
      );
    });

    it("converts an all-null frame", () => {
      const frame = {
        module: null,
        function: null,
        arityOrArgs: null,
        file: null,
        line: null,
        errorInfo: null,
      };

      const result = CallStack.boxFrame(frame);

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.nil(), Type.nil(), Type.nil(), Type.list()]),
      );
    });
  });

  describe("peek()", () => {
    it("returns the innermost frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.equal(CallStack.peek(), enumFrame);
    });

    it("doesn't remove the returned frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.peek();

      assert.deepStrictEqual(CallStack.snapshot(), [myModuleFrame]);
    });

    it("returns undefined when the stack is empty", () => {
      assert.isUndefined(CallStack.peek());
    });
  });

  describe("pop()", () => {
    it("removes the innermost frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);
      CallStack.pop();

      assert.deepStrictEqual(CallStack.snapshot(), [myModuleFrame]);
    });

    it("returns the removed frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.equal(CallStack.pop(), enumFrame);
    });

    it("returns undefined when the stack is empty", () => {
      assert.isUndefined(CallStack.pop());
    });
  });

  describe("push()", () => {
    it("adds the frame to an empty stack", () => {
      CallStack.push(myModuleFrame);

      assert.deepStrictEqual(CallStack.snapshot(), [myModuleFrame]);
    });

    it("adds the frame as the new innermost one", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.deepStrictEqual(CallStack.snapshot(), [enumFrame, myModuleFrame]);
    });
  });

  describe("reset()", () => {
    it("clears the stack", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);
      CallStack.reset();

      assert.deepStrictEqual(CallStack.snapshot(), []);
    });
  });

  describe("snapshot()", () => {
    it("returns an empty array when the stack is empty", () => {
      assert.deepStrictEqual(CallStack.snapshot(), []);
    });

    it("returns the frames innermost first", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.deepStrictEqual(CallStack.snapshot(), [enumFrame, myModuleFrame]);
    });

    it("returns frames by reference", () => {
      CallStack.push(myModuleFrame);

      assert.equal(CallStack.snapshot()[0], myModuleFrame);
    });

    it("returns a copy that a later push doesn't affect", () => {
      CallStack.push(myModuleFrame);

      const snapshot = CallStack.snapshot();
      CallStack.push(enumFrame);

      assert.deepStrictEqual(snapshot, [myModuleFrame]);
    });

    it("returns a copy that a later pop doesn't affect", () => {
      CallStack.push(myModuleFrame);

      const snapshot = CallStack.snapshot();
      CallStack.pop();

      assert.deepStrictEqual(snapshot, [myModuleFrame]);
    });
  });

  describe("unboxTopFrame()", () => {
    const errorInfo = Type.map([
      [Type.atom("cause"), Type.atom("badopt")],
      [Type.atom("module"), Type.atom("erl_stdlib_errors")],
    ]);

    const boxedFrame = (location) =>
      Type.tuple([
        Type.atom("maps"),
        Type.atom("get"),
        Type.list([Type.atom("abc"), Type.integer(123)]),
        location,
      ]);

    it("reads the identity and the args of the innermost entry", () => {
      const stacktrace = Type.list([
        boxedFrame(Type.list()),
        boxedFrame(Type.list()),
      ]);

      assert.deepStrictEqual(CallStack.unboxTopFrame(stacktrace), {
        arityOrArgs: Type.list([Type.atom("abc"), Type.integer(123)]),
        errorInfo: null,
        function: Type.atom("get"),
        module: Type.atom("maps"),
      });
    });

    it("reads a bare arity", () => {
      const frame = Type.tuple([
        Type.atom("maps"),
        Type.atom("get"),
        Type.integer(2),
        Type.list(),
      ]);

      const result = CallStack.unboxTopFrame(Type.list([frame]));

      assert.deepStrictEqual(result.arityOrArgs, Type.integer(2));
    });

    it("reads the error_info map the location names", () => {
      const location = Type.list([
        Type.tuple([Type.atom("file"), Type.charlist("lib/maps.ex")]),
        Type.tuple([Type.atom("error_info"), errorInfo]),
      ]);

      const result = CallStack.unboxTopFrame(Type.list([boxedFrame(location)]));

      assert.deepStrictEqual(result.errorInfo, errorInfo);
    });

    it("resolves a location naming error_info more than once to the first", () => {
      const otherErrorInfo = Type.map([
        [Type.atom("module"), Type.atom("erl_erts_errors")],
      ]);

      const location = Type.list([
        Type.tuple([Type.atom("error_info"), errorInfo]),
        Type.tuple([Type.atom("error_info"), otherErrorInfo]),
      ]);

      const result = CallStack.unboxTopFrame(Type.list([boxedFrame(location)]));

      assert.deepStrictEqual(result.errorInfo, errorInfo);
    });

    it("names no error_info when the location has none", () => {
      const location = Type.list([
        Type.tuple([Type.atom("line"), Type.integer(11)]),
      ]);

      const result = CallStack.unboxTopFrame(Type.list([boxedFrame(location)]));

      assert.isNull(result.errorInfo);
    });

    it("names no error_info when the location isn't a list", () => {
      const result = CallStack.unboxTopFrame(
        Type.list([boxedFrame(Type.atom("abc"))]),
      );

      assert.isNull(result.errorInfo);
    });

    it("returns null when the stacktrace isn't a list", () => {
      assert.isNull(CallStack.unboxTopFrame(Type.atom("abc")));
    });

    it("returns null when the stacktrace is empty", () => {
      assert.isNull(CallStack.unboxTopFrame(Type.list()));
    });

    it("returns null when the innermost entry isn't a tuple", () => {
      assert.isNull(CallStack.unboxTopFrame(Type.list([Type.atom("abc")])));
    });

    it("returns null when the innermost entry isn't a 4-element tuple", () => {
      const frame = Type.tuple([
        Type.atom("maps"),
        Type.atom("get"),
        Type.integer(2),
      ]);

      assert.isNull(CallStack.unboxTopFrame(Type.list([frame])));
    });
  });
});
