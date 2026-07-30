defmodule Hologram.ExJsConsistency.Elixir.String.TokenizerTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/string/tokenizer_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "tokenize/1" do
    test "lowercase identifier" do
      assert String.Tokenizer.tokenize(~c"foo") == {:identifier, ~c"foo", [], 3, true, []}
    end

    test "identifier with underscore and digits" do
      assert String.Tokenizer.tokenize(~c"foo_bar1") ==
               {:identifier, ~c"foo_bar1", [], 8, true, []}
    end

    test "identifier starting with underscore" do
      assert String.Tokenizer.tokenize(~c"_foo") == {:identifier, ~c"_foo", [], 4, true, []}
    end

    test "identifier closed by punctuation" do
      assert String.Tokenizer.tokenize(~c"foo?") ==
               {:identifier, ~c"foo?", [], 4, true, [:punctuation]}
    end

    test "punctuation closes the identifier before the rest" do
      assert String.Tokenizer.tokenize(~c"foo??") ==
               {:identifier, ~c"foo?", ~c"?", 4, true, [:punctuation]}
    end

    test "identifier carrying the at sign" do
      assert String.Tokenizer.tokenize(~c"foo@bar") ==
               {:identifier, ~c"foo@bar", [], 7, true, [:at]}
    end

    test "alias" do
      assert String.Tokenizer.tokenize(~c"FooBar") == {:alias, ~c"FooBar", [], 6, true, []}
    end

    test "alias stops at the dot" do
      assert String.Tokenizer.tokenize(~c"Elixir.Foo") ==
               {:alias, ~c"Elixir", ~c".Foo", 6, true, []}
    end

    test "identifier stops at an ASCII non-identifier character" do
      assert String.Tokenizer.tokenize(~c"foo bar") ==
               {:identifier, ~c"foo", ~c" bar", 3, true, []}
    end

    test "Unicode identifier" do
      assert String.Tokenizer.tokenize(~c"héllo") == {:identifier, ~c"héllo", [], 5, false, []}
    end

    test "Han identifier" do
      assert String.Tokenizer.tokenize(~c"日本語") == {:identifier, ~c"日本語", [], 3, false, []}
    end

    test "uppercase non-ASCII starts an atom" do
      assert String.Tokenizer.tokenize(~c"Ω") == {:atom, ~c"Ω", [], 1, false, []}
    end

    test "NFC-normalizes and flags an unstable identifier" do
      # e followed by combining acute normalizes to é
      assert String.Tokenizer.tokenize([101, 769]) ==
               {:identifier, ~c"é", [], 2, false, [:nfkc]}
    end

    test "micro sign normalizes to Greek mu" do
      assert String.Tokenizer.tokenize([181]) == {:identifier, ~c"μ", [], 1, false, [:nfkc]}
    end

    test "Greek mu combines with any script" do
      assert String.Tokenizer.tokenize(~c"aμ") == {:identifier, ~c"aμ", [], 2, false, []}
    end

    test "underscore separates chunks checked for scripts on their own" do
      assert String.Tokenizer.tokenize(~c"fox_狐") == {:identifier, ~c"fox_狐", [], 5, false, []}
    end

    test "empty input" do
      assert String.Tokenizer.tokenize(~c"") == {:error, :empty}
    end

    test "digit can't start an identifier" do
      assert String.Tokenizer.tokenize(~c"1abc") == {:error, :empty}
    end

    test "at sign can't start an identifier" do
      assert String.Tokenizer.tokenize(~c"@foo") == {:error, :empty}
    end

    test "restricted codepoint can't start an identifier" do
      # fullwidth f is excluded by UTS 39
      assert String.Tokenizer.tokenize(~c"ｆｏｏ") == {:error, :empty}
    end

    test "restricted codepoint inside an identifier is unexpected" do
      # superscript two is excluded by UTS 39
      assert String.Tokenizer.tokenize(~c"x²") == {:error, {:unexpected_token, ~c"x²"}}
    end

    test "mixed scripts are rejected" do
      assert {:error, {:mixed_script, ~c"a日", {prefix, suffix}}} =
               String.Tokenizer.tokenize(~c"a日")

      # The prefix matches the client. The client's suffix explanation is simplified - it lists
      # the characters without their script names.
      assert prefix == ~c"invalid mixed-script identifier found: "
      assert is_list(suffix)
    end

    test "raises FunctionClauseError if the argument is not a list" do
      expected_msg =
        build_function_clause_error_msg("String.Tokenizer.tokenize/1", [:abc], [
          "def tokenize(-[head | tail]-)",
          "def tokenize(-[]-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        :abc
        |> wrap_term()
        |> String.Tokenizer.tokenize()
      end
    end
  end
end
