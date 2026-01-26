"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Uri_String from "../../../assets/js/erlang/uri_string.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/uri_string_test.exs
// Always update both together.

describe("Erlang_Uri_String", () => {
  describe("parse/1", () => {
    const parse = Erlang_Uri_String["parse/1"];

    it("full URI with all components (binary)", () => {
      const uri = Type.bitstring(
        "foo://user@example.com:8042/over/there?name=ferret#nose",
      );
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("fragment"), Type.bitstring("nose")],
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/over/there")],
        [Type.atom("port"), Type.integer(8042)],
        [Type.atom("query"), Type.bitstring("name=ferret")],
        [Type.atom("scheme"), Type.bitstring("foo")],
        [Type.atom("userinfo"), Type.bitstring("user")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("full URI with all components (list)", () => {
      const uri = Type.charlist(
        "foo://user@example.com:8042/over/there?name=ferret#nose",
      );
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("fragment"), Type.charlist("nose")],
        [Type.atom("host"), Type.charlist("example.com")],
        [Type.atom("path"), Type.charlist("/over/there")],
        [Type.atom("port"), Type.integer(8042)],
        [Type.atom("query"), Type.charlist("name=ferret")],
        [Type.atom("scheme"), Type.charlist("foo")],
        [Type.atom("userinfo"), Type.charlist("user")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI without userinfo", () => {
      const uri = Type.bitstring(
        "foo://example.com:8042/over/there?name=ferret#nose",
      );
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("fragment"), Type.bitstring("nose")],
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/over/there")],
        [Type.atom("port"), Type.integer(8042)],
        [Type.atom("query"), Type.bitstring("name=ferret")],
        [Type.atom("scheme"), Type.bitstring("foo")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI without port", () => {
      const uri = Type.bitstring(
        "foo://user@example.com/over/there?name=ferret#nose",
      );
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("fragment"), Type.bitstring("nose")],
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/over/there")],
        [Type.atom("query"), Type.bitstring("name=ferret")],
        [Type.atom("scheme"), Type.bitstring("foo")],
        [Type.atom("userinfo"), Type.bitstring("user")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI without query", () => {
      const uri = Type.bitstring("foo://user@example.com:8042/over/there#nose");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("fragment"), Type.bitstring("nose")],
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/over/there")],
        [Type.atom("port"), Type.integer(8042)],
        [Type.atom("scheme"), Type.bitstring("foo")],
        [Type.atom("userinfo"), Type.bitstring("user")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI without fragment", () => {
      const uri = Type.bitstring(
        "foo://user@example.com:8042/over/there?name=ferret",
      );
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/over/there")],
        [Type.atom("port"), Type.integer(8042)],
        [Type.atom("query"), Type.bitstring("name=ferret")],
        [Type.atom("scheme"), Type.bitstring("foo")],
        [Type.atom("userinfo"), Type.bitstring("user")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("simple HTTP URI", () => {
      const uri = Type.bitstring("http://www.example.com");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("www.example.com")],
        [Type.atom("path"), Type.bitstring("")],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("HTTP URI with path", () => {
      const uri = Type.bitstring("http://www.example.com/path/to/resource");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("www.example.com")],
        [Type.atom("path"), Type.bitstring("/path/to/resource")],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("HTTPS URI with port and query", () => {
      const uri = Type.bitstring("https://example.com:443/search?q=test");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/search")],
        [Type.atom("port"), Type.integer(443)],
        [Type.atom("query"), Type.bitstring("q=test")],
        [Type.atom("scheme"), Type.bitstring("https")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI with IPv6 address", () => {
      const uri = Type.bitstring("http://[2001:db8::1]:8080/path");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("2001:db8::1")],
        [Type.atom("path"), Type.bitstring("/path")],
        [Type.atom("port"), Type.integer(8080)],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI with IPv6 address without port", () => {
      const uri = Type.bitstring("http://[2001:db8::1]/path");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("2001:db8::1")],
        [Type.atom("path"), Type.bitstring("/path")],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI with empty port", () => {
      const uri = Type.bitstring("http://example.com:/path");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/path")],
        [Type.atom("port"), Type.atom("undefined")],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI with port 0", () => {
      const uri = Type.bitstring("http://example.com:0/path");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/path")],
        [Type.atom("port"), Type.integer(0)],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("relative URI (path only)", () => {
      const uri = Type.bitstring("/path/to/resource");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("path"), Type.bitstring("/path/to/resource")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("relative URI with query", () => {
      const uri = Type.bitstring("/path?query=value");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("path"), Type.bitstring("/path")],
        [Type.atom("query"), Type.bitstring("query=value")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("relative URI with fragment", () => {
      const uri = Type.bitstring("/path#section");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("path"), Type.bitstring("/path")],
        [Type.atom("fragment"), Type.bitstring("section")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("fragment only", () => {
      const uri = Type.bitstring("#fragment");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("path"), Type.bitstring("")],
        [Type.atom("fragment"), Type.bitstring("fragment")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("query only", () => {
      const uri = Type.bitstring("?query=value");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("path"), Type.bitstring("")],
        [Type.atom("query"), Type.bitstring("query=value")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("empty URI string", () => {
      const uri = Type.bitstring("");
      const result = parse(uri);

      const expected = Type.map([[Type.atom("path"), Type.bitstring("")]]);

      assert.deepStrictEqual(result, expected);
    });

    it("mailto URI", () => {
      const uri = Type.bitstring("mailto:john@example.com");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("path"), Type.bitstring("john@example.com")],
        [Type.atom("scheme"), Type.bitstring("mailto")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("file URI", () => {
      const uri = Type.bitstring("file:///path/to/file.txt");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("")],
        [Type.atom("path"), Type.bitstring("/path/to/file.txt")],
        [Type.atom("scheme"), Type.bitstring("file")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI with percent-encoded characters", () => {
      const uri = Type.bitstring("http://example.com/path%20with%20spaces");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/path%20with%20spaces")],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI with special characters in query", () => {
      const uri = Type.bitstring("http://example.com?key1=value1&key2=value2");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("")],
        [Type.atom("query"), Type.bitstring("key1=value1&key2=value2")],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("URI with userinfo containing password", () => {
      const uri = Type.bitstring("http://user:password@example.com/path");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("example.com")],
        [Type.atom("path"), Type.bitstring("/path")],
        [Type.atom("scheme"), Type.bitstring("http")],
        [Type.atom("userinfo"), Type.bitstring("user:password")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("invalid UTF-8 binary raises FunctionClauseError", () => {
      const invalid = Type.bitstring([1, 1, 1, 1, 1, 1, 1, 1]);

      assertBoxedError(
        () => parse(invalid),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":uri_string.parse/1", [
          invalid,
        ]),
      );
    });

    it("charlist with non-integer raises ArgumentError", () => {
      const invalid = Type.list([Type.atom("a")]);

      assertBoxedError(
        () => parse(invalid),
        "ArgumentError",
        /not valid character data/, // matches OTP-style message
      );
    });

    it("charlist with out-of-range integer raises FunctionClauseError", () => {
      const invalid = Type.list([Type.integer(1_200_000)]);

      assertBoxedError(
        () => parse(invalid),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":uri_string.parse/1", [
          invalid,
        ]),
      );
    });

    it("URI with IPv6 host and port", () => {
      const uri = Type.bitstring("http://[::1]:8080/");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("::1")],
        [Type.atom("path"), Type.bitstring("/")],
        [Type.atom("port"), Type.integer(8080)],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("bare authority with empty host and port", () => {
      const uri = Type.bitstring("//:80");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("")],
        [Type.atom("path"), Type.bitstring("")],
        [Type.atom("port"), Type.integer(80)],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("missing closing bracket returns invalid_uri", () => {
      const uri = Type.bitstring("http://[::1");
      const result = parse(uri);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.atom("invalid_uri"),
        Type.charlist(":"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("non-numeric port returns invalid_uri", () => {
      const uri = Type.bitstring("http://example.com:abc");
      const result = parse(uri);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.atom("invalid_uri"),
        Type.charlist(":"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("second fragment separator returns invalid_uri", () => {
      const uri = Type.bitstring("http://h/p#f#x");
      const result = parse(uri);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.atom("invalid_uri"),
        Type.charlist(":"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("double query keeps full query text", () => {
      const uri = Type.bitstring("http://h/p?x?y");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("h")],
        [Type.atom("path"), Type.bitstring("/p")],
        [Type.atom("query"), Type.bitstring("x?y")],
        [Type.atom("scheme"), Type.bitstring("http")],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError for non-binary/non-list input", () => {
      const invalidInput = Type.integer(123);

      assertBoxedError(
        () => parse(invalidInput),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":uri_string.parse/1", [
          invalidInput,
        ]),
      );
    });

    it("multiple @ symbols in authority (bare //) returns invalid_uri", () => {
      const uri = Type.bitstring("//a@b@c/path");
      const result = parse(uri);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.atom("invalid_uri"),
        Type.charlist("@"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple @ symbols in authority (with scheme) returns invalid_uri", () => {
      const uri = Type.bitstring("http://a@b@c/path");
      const result = parse(uri);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.atom("invalid_uri"),
        Type.charlist(":"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple @ symbols in authority with port returns invalid_uri", () => {
      const uri = Type.bitstring("http://user@host@extra:8080/path");
      const result = parse(uri);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.atom("invalid_uri"),
        Type.charlist(":"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // Duplicate of the bare // case above removed for clarity.

    it("single @ in userinfo, multiple in path is valid", () => {
      const uri = Type.bitstring("http://user@host/path@with@at");
      const result = parse(uri);

      const expected = Type.map([
        [Type.atom("host"), Type.bitstring("host")],
        [Type.atom("path"), Type.bitstring("/path@with@at")],
        [Type.atom("scheme"), Type.bitstring("http")],
        [Type.atom("userinfo"), Type.bitstring("user")],
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });
});
