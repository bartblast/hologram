"use strict";

import {
  assert,
  contextFixture,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Elixir_Exception from "../../../assets/js/elixir/exception.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

// IMPORTANT!
// Each test here has a related Elixir consistency test in
// test/elixir/hologram/ex_js_consistency/elixir/exception_test.exs.
// Always update both together.
//
// A name needing quotes is decided by Macro.inspect_atom/3, which stands in
// here as a helper that quotes everything - so which names an operator or an
// alias among them is pinned there rather than in the cases below.
describe("Elixir_Exception", () => {
  describe("format_stacktrace/1", () => {
    const frame = (moduleTerm, functionName, arityOrArgs, location) =>
      Type.tuple([
        moduleTerm,
        Type.atom(functionName),
        arityOrArgs,
        Type.list(location),
      ]);

    const fileEntry = (path) =>
      Type.tuple([Type.atom("file"), Type.charlist(path)]);

    const lineEntry = (line) =>
      Type.tuple([Type.atom("line"), Type.integer(line)]);

    const render = (...frames) =>
      Bitstring.toText(
        Elixir_Exception["format_stacktrace/1"](Type.list(frames)),
      );

    afterEach(() => {
      ERTS.appVersions = {};
      ERTS.moduleMetadata = {};
    });

    it("indents each frame and ends the line it is on", () => {
      const result = render(
        frame(Type.alias("MyModule"), "my_fun", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
        frame(Type.alias("MyModule"), "my_other_fun", Type.integer(2), [
          fileEntry("lib/my_module.ex"),
          lineEntry(22),
        ]),
      );

      assert.equal(
        result,
        "    lib/my_module.ex:11: MyModule.my_fun/1\n" +
          "    lib/my_module.ex:22: MyModule.my_other_fun/2\n",
      );
    });

    it("renders a stacktrace carrying no frames as a line of its own", () => {
      assert.equal(render(), "\n");
    });

    // The only case whose values differ from its Elixir twin: a module here is
    // told which application owns it, whereas the server can only be shown a
    // module that really belongs to one. The shape being pinned is the same.
    it("names the application a module was compiled into", () => {
      ERTS.moduleMetadata = {MyModule: {app: "my_app", file: null}};
      ERTS.appVersions = {my_app: "1.2.3"};

      const result = render(
        frame(Type.alias("MyModule"), "my_fun", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      );

      assert.equal(
        result,
        "    (my_app 1.2.3) lib/my_module.ex:11: MyModule.my_fun/1\n",
      );
    });

    it("names an application carrying no version by its name alone", () => {
      ERTS.moduleMetadata = {MyModule: {app: "my_app", file: null}};

      const result = render(
        frame(Type.alias("MyModule"), "my_fun", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      );

      assert.equal(
        result,
        "    (my_app) lib/my_module.ex:11: MyModule.my_fun/1\n",
      );
    });

    it("names an Erlang module as the atom it is", () => {
      const result = render(
        frame(Type.atom("my_module"), "my_fun", Type.integer(2), [
          fileEntry("my_module.erl"),
          lineEntry(11),
        ]),
      );

      assert.equal(result, "    my_module.erl:11: :my_module.my_fun/2\n");
    });

    it("places a frame carrying a file but no line by its file alone", () => {
      const result = render(
        frame(Type.alias("MyModule"), "my_fun", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
        ]),
      );

      assert.equal(result, "    lib/my_module.ex: MyModule.my_fun/1\n");
    });

    it("places a frame by its file alone when the line it names is zero", () => {
      const result = render(
        frame(Type.alias("MyModule"), "my_fun", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(0),
        ]),
      );

      assert.equal(result, "    lib/my_module.ex: MyModule.my_fun/1\n");
    });

    it("names the column a frame reached when it carries one", () => {
      const result = render(
        frame(Type.alias("MyModule"), "my_fun", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
          Type.tuple([Type.atom("column"), Type.integer(5)]),
        ]),
      );

      assert.equal(result, "    lib/my_module.ex:11:5: MyModule.my_fun/1\n");
    });

    it("places a frame carrying no location by what was running alone", () => {
      const result = render(
        frame(Type.alias("MyModule"), "my_fun", Type.integer(1), []),
      );

      assert.equal(result, "    MyModule.my_fun/1\n");
    });

    it("names the arguments a frame kept in place of its arity", () => {
      const result = render(
        frame(
          Type.alias("MyModule"),
          "my_fun",
          Type.list([Type.atom("abc"), Type.integer(1)]),
          [fileEntry("lib/my_module.ex"), lineEntry(11)],
        ),
      );

      assert.equal(
        result,
        "    lib/my_module.ex:11: MyModule.my_fun(:abc, 1)\n",
      );
    });

    it("names an anonymous function after the one it was defined in", () => {
      const result = render(
        frame(Type.alias("MyModule"), "-my_fun/2-fun-0-", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      );

      assert.equal(
        result,
        "    lib/my_module.ex:11: anonymous fn/1 in MyModule.my_fun/2\n",
      );
    });

    // Elixir generates names for more than anonymous functions, and only the
    // ones it generated for those name the function they came from.
    it("keeps a generated name that names no function it came from", () => {
      const result = render(
        frame(
          Type.alias("MyModule"),
          "-map/2-lists^map/1-1-",
          Type.integer(2),
          [fileEntry("lib/my_module.ex"), lineEntry(11)],
        ),
      );

      assert.equal(
        result,
        '    lib/my_module.ex:11: MyModule."-map/2-lists^map/1-1-"/2\n',
      );
    });

    it("writes a function name that could not be written as it stands quoted", () => {
      const result = render(
        frame(Type.alias("MyModule"), "my fun", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      );

      assert.equal(result, '    lib/my_module.ex:11: MyModule."my fun"/1\n');
    });

    // The entries the compiler generates for a module body and a file body name
    // what they are rather than a function.
    it("names a frame generated for a module body", () => {
      const result = render(
        frame(Type.alias("MyModule"), "__MODULE__", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      );

      assert.equal(result, "    lib/my_module.ex:11: (module)\n");
    });

    it("names a frame generated for a file body", () => {
      const result = render(
        frame(Type.alias("MyModule"), "__FILE__", Type.integer(1), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      );

      assert.equal(result, "    lib/my_module.ex:11: (file)\n");
    });

    it("names the module a frame taken from a macro environment came from", () => {
      const result = render(
        frame(Type.alias("MyModule"), "__MODULE__", Type.integer(0), [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      );

      assert.equal(result, "    lib/my_module.ex:11: MyModule (module)\n");
    });

    // A frame can name an anonymous function rather than a module and a name.
    it("names a frame carrying a function in place of a module and a name", () => {
      const fun = Type.anonymousFunction(0, [], contextFixture());

      const result = render(
        Type.tuple([
          fun,
          Type.integer(0),
          Type.list([fileEntry("lib/my_module.ex"), lineEntry(11)]),
        ]),
      );

      assert.equal(
        result,
        `    lib/my_module.ex:11: ${Interpreter.inspect(fun)}/0\n`,
      );
    });
  });
});
