defmodule Hologram.ExJsConsistency.Elixir.URITest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/uri_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "encode/2, with &URI.char_unreserved?/1 predicate" do
    test "encodes empty string" do
      assert URI.encode("", &URI.char_unreserved?/1) == ""
    end

    test "does not encode unreserved ASCII alphanumeric characters" do
      string = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

      assert URI.encode(string, &URI.char_unreserved?/1) == string
    end

    test "does not encode unreserved special characters: - . _ ~" do
      string = "-._~"

      assert URI.encode(string, &URI.char_unreserved?/1) == string
    end

    test "encodes reserved URI characters" do
      assert URI.encode(":/?#[]@!$&'()*+,;=", &URI.char_unreserved?/1) ==
               "%3A%2F%3F%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D"
    end

    test "encodes UTF-8 multi-byte characters" do
      assert URI.encode("全息图", &URI.char_unreserved?/1) == "%E5%85%A8%E6%81%AF%E5%9B%BE"
    end

    test "handles already percent-encoded strings (double encodes)" do
      assert URI.encode("hello%20world", &URI.char_unreserved?/1) == "hello%2520world"
    end

    test "encodes control characters" do
      assert URI.encode("line1\nline2\ttab", &URI.char_unreserved?/1) == "line1%0Aline2%09tab"
    end
  end

  describe "encode/2, with custom predicate" do
    test "encodes characters not matching custom predicate" do
      # Custom predicate that only allows lowercase letters a-z
      predicate = fn char -> char >= 97 and char <= 122 end

      assert URI.encode("Hello123", predicate) == "%48ello%31%32%33"
    end

    test "encodes all characters when predicate always returns false" do
      predicate = fn _char -> false end

      assert URI.encode("abc", predicate) == "%61%62%63"
    end

    test "encodes no characters when predicate always returns true" do
      predicate = fn _char -> true end
      string = "Hello World!"

      assert URI.encode(string, predicate) == string
    end
  end

  describe "encode/2, error cases" do
    test "raises FunctionClauseError when first argument is not a bitstring" do
      expected_msg =
        build_function_clause_error_msg("URI.encode/2", [:hello, &URI.char_unreserved?/1], [
          "def encode(string, predicate) when -is_binary(string)- and is_function(predicate, 1)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        URI.encode(:hello, &URI.char_unreserved?/1)
      end
    end

    test "raises FunctionClauseError when first argument is a non-binary bitstring" do
      string = <<1::1, 0::1, 1::1, 0::1>>

      expected_msg =
        build_function_clause_error_msg("URI.encode/2", [string, &URI.char_unreserved?/1], [
          "def encode(string, predicate) when -is_binary(string)- and is_function(predicate, 1)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        URI.encode(string, &URI.char_unreserved?/1)
      end
    end

    test "raises FunctionClauseError when second argument is not a function" do
      expected_msg =
        build_function_clause_error_msg("URI.encode/2", ["hello", :not_a_function], [
          "def encode(string, predicate) when is_binary(string) and -is_function(predicate, 1)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        URI.encode("hello", :not_a_function)
      end
    end

    test "raises FunctionClauseError when predicate arity is not 1" do
      predicate = fn _a, _b -> true end

      expected_msg =
        build_function_clause_error_msg("URI.encode/2", ["hello", predicate], [
          "def encode(string, predicate) when is_binary(string) and -is_function(predicate, 1)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        URI.encode("hello", predicate)
      end
    end
  end
end
