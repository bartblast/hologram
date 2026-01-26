defmodule Hologram.ExJsConsistency.Erlang.UriStringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/uri_string_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "parse/1" do
    test "full URI with all components (binary)" do
      assert :uri_string.parse("foo://user@example.com:8042/over/there?name=ferret#nose") ==
               %{
                 fragment: "nose",
                 host: "example.com",
                 path: "/over/there",
                 port: 8042,
                 query: "name=ferret",
                 scheme: "foo",
                 userinfo: "user"
               }
    end

    test "full URI with all components (list)" do
      assert :uri_string.parse(~c"foo://user@example.com:8042/over/there?name=ferret#nose") ==
               %{
                 fragment: ~c"nose",
                 host: ~c"example.com",
                 path: ~c"/over/there",
                 port: 8042,
                 query: ~c"name=ferret",
                 scheme: ~c"foo",
                 userinfo: ~c"user"
               }
    end

    test "URI without userinfo" do
      assert :uri_string.parse("foo://example.com:8042/over/there?name=ferret#nose") ==
               %{
                 fragment: "nose",
                 host: "example.com",
                 path: "/over/there",
                 port: 8042,
                 query: "name=ferret",
                 scheme: "foo"
               }
    end

    test "URI without port" do
      assert :uri_string.parse("foo://user@example.com/over/there?name=ferret#nose") ==
               %{
                 fragment: "nose",
                 host: "example.com",
                 path: "/over/there",
                 query: "name=ferret",
                 scheme: "foo",
                 userinfo: "user"
               }
    end

    test "URI without query" do
      assert :uri_string.parse("foo://user@example.com:8042/over/there#nose") ==
               %{
                 fragment: "nose",
                 host: "example.com",
                 path: "/over/there",
                 port: 8042,
                 scheme: "foo",
                 userinfo: "user"
               }
    end

    test "URI without fragment" do
      assert :uri_string.parse("foo://user@example.com:8042/over/there?name=ferret") ==
               %{
                 host: "example.com",
                 path: "/over/there",
                 port: 8042,
                 query: "name=ferret",
                 scheme: "foo",
                 userinfo: "user"
               }
    end

    test "simple HTTP URI" do
      assert :uri_string.parse("http://www.example.com") ==
               %{
                 host: "www.example.com",
                 path: "",
                 scheme: "http"
               }
    end

    test "HTTP URI with path" do
      assert :uri_string.parse("http://www.example.com/path/to/resource") ==
               %{
                 host: "www.example.com",
                 path: "/path/to/resource",
                 scheme: "http"
               }
    end

    test "HTTPS URI with port and query" do
      assert :uri_string.parse("https://example.com:443/search?q=test") ==
               %{
                 host: "example.com",
                 path: "/search",
                 port: 443,
                 query: "q=test",
                 scheme: "https"
               }
    end

    test "URI with IPv6 address" do
      assert :uri_string.parse("http://[2001:db8::1]:8080/path") ==
               %{
                 host: "2001:db8::1",
                 path: "/path",
                 port: 8080,
                 scheme: "http"
               }
    end

    test "URI with IPv6 address without port" do
      assert :uri_string.parse("http://[2001:db8::1]/path") ==
               %{
                 host: "2001:db8::1",
                 path: "/path",
                 scheme: "http"
               }
    end

    test "URI with empty port" do
      assert :uri_string.parse("http://example.com:/path") ==
               %{
                 host: "example.com",
                 path: "/path",
                 port: :undefined,
                 scheme: "http"
               }
    end

    test "relative URI (path only)" do
      assert :uri_string.parse("/path/to/resource") ==
               %{
                 path: "/path/to/resource"
               }
    end

    test "relative URI with query" do
      assert :uri_string.parse("/path?query=value") ==
               %{
                 path: "/path",
                 query: "query=value"
               }
    end

    test "relative URI with fragment" do
      assert :uri_string.parse("/path#section") ==
               %{
                 path: "/path",
                 fragment: "section"
               }
    end

    test "fragment only" do
      assert :uri_string.parse("#fragment") ==
               %{
                 path: "",
                 fragment: "fragment"
               }
    end

    test "query only" do
      assert :uri_string.parse("?query=value") ==
               %{
                 path: "",
                 query: "query=value"
               }
    end

    test "empty URI string" do
      assert :uri_string.parse("") ==
               %{
                 path: ""
               }
    end

    test "mailto URI" do
      assert :uri_string.parse("mailto:john@example.com") ==
               %{
                 path: "john@example.com",
                 scheme: "mailto"
               }
    end

    test "file URI" do
      assert :uri_string.parse("file:///path/to/file.txt") ==
               %{
                 host: "",
                 path: "/path/to/file.txt",
                 scheme: "file"
               }
    end

    test "URI with percent-encoded characters" do
      assert :uri_string.parse("http://example.com/path%20with%20spaces") ==
               %{
                 host: "example.com",
                 path: "/path%20with%20spaces",
                 scheme: "http"
               }
    end

    test "URI with special characters in query" do
      assert :uri_string.parse("http://example.com?key1=value1&key2=value2") ==
               %{
                 host: "example.com",
                 path: "",
                 query: "key1=value1&key2=value2",
                 scheme: "http"
               }
    end

    test "URI with userinfo containing password" do
      assert :uri_string.parse("http://user:password@example.com/path") ==
               %{
                 host: "example.com",
                 path: "/path",
                 scheme: "http",
                 userinfo: "user:password"
               }
    end

    test "invalid UTF-8 binary raises FunctionClauseError" do
      assert_error FunctionClauseError,
                   ~r/parse_scheme_start/,
                   fn -> :uri_string.parse(<<255>>) end
    end

    test "charlist with non-integer raises ArgumentError" do
      assert_error ArgumentError,
                   ~r/not valid character data/,
                   fn -> :uri_string.parse([:a]) end
    end

    test "charlist with out-of-range integer raises FunctionClauseError" do
      assert_error FunctionClauseError,
                   ~r/parse_scheme_start/,
                   fn -> :uri_string.parse([1_200_000]) end
    end

    test "URI with IPv6 host and port" do
      assert :uri_string.parse("http://[::1]:8080/") ==
               %{
                 host: "::1",
                 path: "/",
                 port: 8080,
                 scheme: "http"
               }
    end

    test "bare authority with empty host and port" do
      assert :uri_string.parse("//:80") ==
               %{
                 host: "",
                 path: "",
                 port: 80
               }
    end

    test "missing closing bracket returns invalid_uri" do
      assert :uri_string.parse("http://[::1") == {:error, :invalid_uri, ~c":"}
    end

    test "non-numeric port returns invalid_uri" do
      assert :uri_string.parse("http://example.com:abc") == {:error, :invalid_uri, ~c":"}
    end

    test "second fragment separator returns invalid_uri" do
      assert :uri_string.parse("http://h/p#f#x") == {:error, :invalid_uri, ~c":"}
    end

    test "double query keeps full query text" do
      assert :uri_string.parse("http://h/p?x?y") ==
               %{
                 host: "h",
                 path: "/p",
                 query: "x?y",
                 scheme: "http"
               }
    end

    test "raises FunctionClauseError for non-binary/non-list input" do
      expected_msg = build_function_clause_error_msg(":uri_string.parse/1", [123])

      assert_error FunctionClauseError,
                   expected_msg,
                   fn -> :uri_string.parse(123) end
    end

    test "multiple @ symbols in authority (bare //) returns invalid_uri" do
      assert :uri_string.parse("//a@b@c/path") == {:error, :invalid_uri, ~c"@"}
    end

    test "multiple @ symbols in authority (with scheme) returns invalid_uri" do
      assert :uri_string.parse("http://a@b@c/path") == {:error, :invalid_uri, ~c":"}
    end

    test "multiple @ symbols in authority with port returns invalid_uri" do
      assert :uri_string.parse("http://user@host@extra:8080/path") ==
               {:error, :invalid_uri, ~c":"}
    end

    test "single @ in userinfo, multiple in path is valid" do
      assert :uri_string.parse("http://user@host/path@with@at") ==
               %{
                 host: "host",
                 path: "/path@with@at",
                 scheme: "http",
                 userinfo: "user"
               }
    end
  end
end
