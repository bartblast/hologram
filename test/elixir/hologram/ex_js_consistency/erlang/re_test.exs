defmodule Hologram.ExJsConsistency.Erlang.ReTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/re_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  # The client runtime targets PCRE2 semantics, available on the server since OTP 28
  if String.to_integer(System.otp_release()) >= 28 do
    defp assert_ok_result(result, capture_count, unicode_flag, use_crlf) do
      assert {:ok, re_pattern} = result
      assert_re_pattern(re_pattern, capture_count, unicode_flag, use_crlf)
    end

    defp assert_re_pattern(re_pattern, capture_count, unicode_flag, use_crlf) do
      assert {:re_pattern, ^capture_count, ^unicode_flag, ^use_crlf, _code} = re_pattern
    end

    describe "compile/1" do
      test "compiles a pattern with default options" do
        assert_ok_result(:re.compile("(a)b"), 1, 0, 0)
      end

      test "returns a compile error tuple on invalid pattern" do
        assert :re.compile("a{2,1}") ==
                 {:error, {~c"numbers out of order in {} quantifier", 5}}
      end

      test "raises ArgumentError on non-iodata pattern" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.compile(:abc) end
      end
    end

    describe "compile/2" do
      test "compiles a binary pattern" do
        assert_ok_result(:re.compile("ab", []), 0, 0, 0)
      end

      test "compiles a charlist pattern" do
        assert_ok_result(:re.compile(~c"ab", []), 0, 0, 0)
      end

      test "compiles nested iodata with an improper binary tail" do
        assert_ok_result(:re.compile([~c"a(", "b)" | "c"], []), 1, 0, 0)
      end

      test "compiles an empty pattern" do
        assert_ok_result(:re.compile("", []), 0, 0, 0)
      end

      test "counts capture groups" do
        assert_ok_result(:re.compile("(a)(b)(?<n>c)", []), 3, 0, 0)
      end

      test "counts branch reset groups with shared numbers" do
        assert_ok_result(:re.compile("(?|(a)|(b))", []), 1, 0, 0)
      end

      test "sets the unicode flag with the unicode option" do
        assert_ok_result(:re.compile("ab", [:unicode]), 0, 1, 0)
      end

      test "doesn't set the unicode flag with a UTF pattern verb" do
        assert_ok_result(:re.compile("(*UTF)ab", []), 0, 0, 0)
      end

      test "decodes a UTF-8 binary pattern with the unicode option" do
        assert_ok_result(:re.compile("é{2}", [:unicode]), 0, 1, 0)
      end

      test "decodes byte input as UTF-8 with a UTF pattern verb" do
        assert_ok_result(:re.compile("(*UTF)é{2}", []), 0, 0, 0)
      end

      test "treats bytes as latin-1 without the unicode option" do
        assert_ok_result(:re.compile(<<233, 255>>, []), 0, 0, 0)
      end

      test "accepts unicode char data with the unicode option" do
        assert_ok_result(:re.compile([233, "é"], [:unicode]), 0, 1, 0)
      end

      test "sets the use_crlf flag with a crlf newline option" do
        assert_ok_result(:re.compile("ab", [{:newline, :crlf}]), 0, 0, 1)
      end

      test "sets the use_crlf flag with an any newline option" do
        assert_ok_result(:re.compile("ab", [{:newline, :any}]), 0, 0, 1)
      end

      test "doesn't set the use_crlf flag with a cr newline option" do
        assert_ok_result(:re.compile("ab", [{:newline, :cr}]), 0, 0, 0)
      end

      test "sets the use_crlf flag with a newline verb" do
        assert_ok_result(:re.compile("(*CRLF)ab", []), 0, 0, 1)
      end

      test "newline verb beats the newline option" do
        assert_ok_result(:re.compile("(*LF)ab", [{:newline, :crlf}]), 0, 0, 0)
      end

      test "last newline option wins" do
        assert_ok_result(:re.compile("ab", [{:newline, :crlf}, {:newline, :lf}]), 0, 0, 0)
      end

      test "last newline verb wins" do
        assert_ok_result(:re.compile("(*CRLF)(*LF)ab", []), 0, 0, 0)
      end

      test "accepts all compile options" do
        opts = [
          :anchored,
          :bsr_anycrlf,
          :bsr_unicode,
          :caseless,
          :dollar_endonly,
          :dotall,
          :dupnames,
          :extended,
          :firstline,
          :multiline,
          :no_auto_capture,
          :no_start_optimize,
          :ucp,
          :ungreedy
        ]

        assert_ok_result(:re.compile("ab", opts), 0, 0, 0)
      end

      test "accepts duplicated options" do
        assert_ok_result(:re.compile("ab", [:caseless, :caseless]), 0, 0, 0)
      end

      test "returns a compile error tuple on invalid pattern" do
        assert :re.compile("a{2,1}", []) ==
                 {:error, {~c"numbers out of order in {} quantifier", 5}}
      end

      test "returns error position as byte offset in unicode mode" do
        assert :re.compile("é(", [:unicode]) ==
                 {:error, {~c"missing closing parenthesis", 3}}
      end

      test "returns a UTF-8 error tuple for invalid UTF-8 binary in unicode mode" do
        assert :re.compile(<<255, ?a>>, [:unicode]) ==
                 {:error, {~c"UTF-8 error: illegal byte (0xfe or 0xff)", 0}}
      end

      test "returns a UTF-8 error tuple for invalid UTF-8 after a UTF pattern verb" do
        assert :re.compile(["(*UTF)" | <<255>>], []) ==
                 {:error, {~c"UTF-8 error: illegal byte (0xfe or 0xff)", 6}}
      end

      test "returns a disabled UTF error with never_utf option and a UTF pattern verb" do
        assert :re.compile("(*UTF)ab", [:never_utf]) ==
                 {:error, {~c"using UTF is disabled by the application", 6}}
      end

      test "disabled UTF error beats UTF-8 validation" do
        assert :re.compile(["(*UTF)" | <<255>>], [:never_utf]) ==
                 {:error, {~c"using UTF is disabled by the application", 6}}
      end

      test "returns a disabled UTF error with unicode and never_utf options" do
        assert :re.compile("ab", [:unicode, :never_utf]) ==
                 {:error, {~c"using UTF is disabled by the application", 0}}
      end

      test "raises ArgumentError on non-iodata pattern" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.compile(:abc, []) end
      end

      test "raises ArgumentError on non-binary bitstring pattern" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.compile(<<1::1>>, []) end
      end

      test "raises ArgumentError on code point above 255 in byte mode" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.compile([256], []) end
      end

      test "raises ArgumentError on improper integer tail" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.compile([?a | ?b], []) end
      end

      test "raises ArgumentError on non-binary bitstring pattern in unicode mode" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.compile(<<1::1>>, [:unicode]) end
      end

      test "raises plain ArgumentError on non-chardata pattern in unicode mode" do
        assert_error ArgumentError, "argument error", fn ->
          :re.compile(:abc, [:unicode])
        end
      end

      test "raises plain ArgumentError on surrogate code point in unicode mode" do
        assert_error ArgumentError, "argument error", fn ->
          :re.compile([0xD800], [:unicode])
        end
      end

      test "raises plain ArgumentError on code point above 0x10FFFF in unicode mode" do
        assert_error ArgumentError, "argument error", fn ->
          :re.compile([0x110000], [:unicode])
        end
      end

      test "raises plain ArgumentError on invalid UTF-8 binary inside list in unicode mode" do
        assert_error ArgumentError, "argument error", fn ->
          :re.compile([<<255>>], [:unicode])
        end
      end

      test "raises plain ArgumentError on improper integer tail in unicode mode" do
        assert_error ArgumentError, "argument error", fn ->
          :re.compile([?a | ?b], [:unicode])
        end
      end

      test "raises ArgumentError on invalid option" do
        assert_error ArgumentError,
                     build_argument_error_msg(2, "invalid options"),
                     fn -> :re.compile("ab", [:bad]) end
      end

      test "raises ArgumentError on run-only option" do
        assert_error ArgumentError,
                     build_argument_error_msg(2, "invalid options"),
                     fn -> :re.compile("ab", [:notempty]) end
      end

      test "raises ArgumentError on non-atom option" do
        assert_error ArgumentError,
                     build_argument_error_msg(2, "invalid options"),
                     fn -> :re.compile("ab", [1]) end
      end

      test "raises ArgumentError on invalid newline type" do
        assert_error ArgumentError,
                     build_argument_error_msg(2, "invalid options"),
                     fn -> :re.compile("ab", [{:newline, :xx}]) end
      end

      test "raises ArgumentError on non-list options" do
        assert_error ArgumentError,
                     build_argument_error_msg(2, "invalid options"),
                     fn -> :re.compile("ab", :unicode) end
      end

      test "raises ArgumentError on improper options list" do
        assert_error ArgumentError,
                     build_argument_error_msg(2, "invalid options"),
                     fn -> :re.compile("ab", [:caseless | :foo]) end
      end

      test "raises ArgumentError with both bullets on non-iodata pattern and invalid options" do
        expected_msg = """
        errors were found at the given arguments:

          * 1st argument: not an iodata term
          * 2nd argument: invalid options
        """

        assert_error ArgumentError, expected_msg, fn -> :re.compile(:abc, [:bad]) end
      end
    end
  end

  # :re.import/1 is available since OTP 28.1. Feature detection instead of a
  # version check, because System.otp_release/0 returns only the major version,
  # and reading the minor version from the OTP_VERSION release file is more
  # brittle. Code.ensure_loaded?/1 is required, because this runs at compile
  # time, when :re may not be loaded yet, and function_exported?/3 returns
  # false for unloaded modules.
  if Code.ensure_loaded?(:re) and function_exported?(:re, :import, 1) do
    describe "import/1" do
      test "imports an exported pattern" do
        {:ok, exported} = :re.compile("(a)b", [:export, :caseless])

        assert_re_pattern(:re.import(exported), 1, 0, 0)
      end

      test "sets the unicode flag from the exported options" do
        {:ok, exported} = :re.compile("(a)é", [:export, :unicode])

        assert_re_pattern(:re.import(exported), 1, 1, 0)
      end

      test "sets the use_crlf flag from the exported options" do
        {:ok, exported} = :re.compile("a", [:export, {:newline, :crlf}])

        assert_re_pattern(:re.import(exported), 0, 0, 1)
      end

      test "raises ArgumentError on non-tuple term" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an exported regular expression"),
                     fn -> :re.import(:foo) end
      end

      test "raises ArgumentError on wrong tuple tag" do
        {:ok, exported} = :re.compile("ab", [:export])
        tampered = :erlang.setelement(1, exported, :bad)

        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an exported regular expression"),
                     fn -> :re.import(tampered) end
      end

      test "raises ArgumentError on wrong tuple size" do
        {:ok, exported} = :re.compile("ab", [:export])
        truncated = :erlang.delete_element(5, exported)

        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an exported regular expression"),
                     fn -> :re.import(truncated) end
      end

      test "raises ArgumentError on tampered header magic" do
        {:ok, exported} = :re.compile("ab", [:export])
        tampered = :erlang.setelement(2, exported, <<"XX-PCRE2", 0, 0, 0, 0, 0, 0>>)

        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an exported regular expression"),
                     fn -> :re.import(tampered) end
      end

      test "raises ArgumentError on truncated header" do
        {:ok, exported} = :re.compile("ab", [:export])
        tampered = :erlang.setelement(2, exported, "re-PCRE2")

        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an exported regular expression"),
                     fn -> :re.import(tampered) end
      end

      test "raises ArgumentError on tampered code blob" do
        {:ok, exported} = :re.compile("ab", [:export])
        tampered = :erlang.setelement(5, exported, <<1, 2, 3>>)

        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an exported regular expression"),
                     fn -> :re.import(tampered) end
      end
    end
  end

  if String.to_integer(System.otp_release()) >= 28 do
    describe "inspect/2" do
      test "returns an empty namelist without named groups" do
        {:ok, compiled} = :re.compile("(a)(b)")

        assert :re.inspect(compiled, :namelist) == {:namelist, []}
      end

      test "returns group names sorted by byte order" do
        {:ok, compiled} = :re.compile("(?<zz>a)(?<aa>b)(?<mm>c)")

        assert :re.inspect(compiled, :namelist) == {:namelist, ["aa", "mm", "zz"]}
      end

      test "deduplicates names with the dupnames option" do
        {:ok, compiled} = :re.compile("(?<x>a)|(?<x>b)", [:dupnames])

        assert :re.inspect(compiled, :namelist) == {:namelist, ["x"]}
      end

      test "returns unicode group names" do
        {:ok, compiled} = :re.compile("(?<héé>a)", [:unicode])

        assert :re.inspect(compiled, :namelist) == {:namelist, ["héé"]}
      end

      test "raises ArgumentError on non-tuple pattern" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not a compiled regular expression"),
                     fn -> :re.inspect(:foo, :namelist) end
      end

      test "raises ArgumentError on unknown pattern reference" do
        re_pattern = {:re_pattern, 0, 0, 0, make_ref()}

        assert_error ArgumentError,
                     build_argument_error_msg(1, "not a compiled regular expression"),
                     fn -> :re.inspect(re_pattern, :namelist) end
      end

      test "raises ArgumentError on invalid item" do
        {:ok, compiled} = :re.compile("ab")

        assert_error ArgumentError,
                     build_argument_error_msg(2, "not a valid item"),
                     fn -> :re.inspect(compiled, :foo) end
      end

      test "raises ArgumentError on bad pattern before bad item" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not a compiled regular expression"),
                     fn -> :re.inspect(:foo, :bar) end
      end
    end

    describe "run/3" do
      test "matches with a raw binary pattern" do
        assert :re.run("abbc", "b+", []) == {:match, [{1, 2}]}
      end

      test "matches with a raw charlist pattern" do
        assert :re.run("abbc", ~c"b+", []) == {:match, [{1, 2}]}
      end

      test "matches with a compiled pattern" do
        {:ok, compiled} = :re.compile("b+")

        assert :re.run("abbc", compiled, []) == {:match, [{1, 2}]}
      end

      test "matches at the leftmost position" do
        assert :re.run("abbb", "b+", []) == {:match, [{1, 3}]}
      end

      test "matches on the interpreter route" do
        assert :re.run("abc", "b\\Kc", []) == {:match, [{2, 1}]}
      end

      test "matches an iodata subject" do
        assert :re.run(["ab" | "bc"], "b+", []) == {:match, [{1, 2}]}
      end

      test "matches an empty pattern on an empty subject" do
        assert :re.run("", "", []) == {:match, [{0, 0}]}
      end

      test "returns nomatch without a match" do
        assert :re.run("abc", "x", []) == :nomatch
      end

      test "returns capture group index tuples" do
        assert :re.run("abc", "(a)(b)(c)", []) ==
                 {:match, [{0, 3}, {0, 1}, {1, 1}, {2, 1}]}
      end

      test "returns {-1, 0} for unset group before a set group" do
        assert :re.run("b", "(a)|(b)", []) == {:match, [{0, 1}, {-1, 0}, {0, 1}]}
      end

      test "omits trailing unset groups" do
        assert :re.run("ab", "(a)(b)(x)?(y)?", []) ==
                 {:match, [{0, 2}, {0, 1}, {1, 1}]}
      end

      test "compiles a raw pattern with compile options" do
        assert :re.run("ABC", "abc", [:caseless]) == {:match, [{0, 3}]}
      end

      test "anchored option matches at the start" do
        assert :re.run("abc", "a", [:anchored]) == {:match, [{0, 1}]}
      end

      test "anchored option pins the match to the start" do
        assert :re.run("abc", "b", [:anchored]) == :nomatch
      end

      test "anchored option works with a compiled pattern" do
        {:ok, compiled} = :re.compile("b")

        assert :re.run("abc", compiled, [:anchored]) == :nomatch
      end

      test "compile-time anchored pattern matches at the start" do
        {:ok, compiled} = :re.compile("b", [:anchored])

        assert :re.run("bbc", compiled, []) == {:match, [{0, 1}]}
      end

      test "compile-time anchored pattern pins the match" do
        {:ok, compiled} = :re.compile("b", [:anchored])

        assert :re.run("abc", compiled, []) == :nomatch
      end

      test "returns byte offsets with the unicode option" do
        assert :re.run("éb", "b", [:unicode]) == {:match, [{2, 1}]}
      end

      test "decodes the subject with a unicode compiled pattern" do
        {:ok, compiled} = :re.compile("é", [:unicode])

        assert :re.run("aéb", compiled, []) == {:match, [{1, 2}]}
      end

      test "accepts unicode char data subject" do
        assert :re.run([233, ?b], "b", [:unicode]) == {:match, [{2, 1}]}
      end

      test "raises ArgumentError on non-iodata subject" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.run(:abc, "a", []) end
      end

      test "raises ArgumentError on non-binary bitstring subject" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.run(<<1::1>>, "a", []) end
      end

      test "raises ArgumentError on subject code point above 255 in byte mode" do
        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.run([256], "a", []) end
      end

      test "raises ArgumentError on non-iodata pattern" do
        assert_error ArgumentError,
                     build_argument_error_msg(
                       2,
                       "neither an iodata term nor a compiled regular expression"
                     ),
                     fn -> :re.run("x", :foo, []) end
      end

      test "raises ArgumentError on non-binary bitstring pattern" do
        assert_error ArgumentError,
                     build_argument_error_msg(
                       2,
                       "neither an iodata term nor a compiled regular expression"
                     ),
                     fn -> :re.run("x", <<1::1>>, []) end
      end

      test "raises ArgumentError on pattern code point above 255 in byte mode" do
        assert_error ArgumentError,
                     build_argument_error_msg(
                       2,
                       "neither an iodata term nor a compiled regular expression"
                     ),
                     fn -> :re.run("x", [256], []) end
      end

      test "raises ArgumentError on unknown compiled pattern reference" do
        re_pattern = {:re_pattern, 0, 0, 0, make_ref()}

        assert_error ArgumentError,
                     build_argument_error_msg(
                       2,
                       "neither an iodata term nor a compiled regular expression"
                     ),
                     fn -> :re.run("x", re_pattern, []) end
      end

      test "raises ArgumentError on non-chardata pattern with the unicode option" do
        assert_error ArgumentError,
                     build_argument_error_msg(
                       2,
                       "neither an iodata term nor a compiled regular expression"
                     ),
                     fn -> :re.run("x", :foo, [:unicode]) end
      end

      test "raises ArgumentError on invalid raw pattern" do
        expected_msg =
          build_argument_error_msg(
            2,
            "could not parse regular expression\nnumbers out of order in {} quantifier on character 5"
          )

        assert_error ArgumentError, expected_msg, fn -> :re.run("abc", "a{2,1}", []) end
      end

      test "raises ArgumentError with byte error position in unicode mode" do
        expected_msg =
          build_argument_error_msg(
            2,
            "could not parse regular expression\nmissing closing parenthesis on character 3"
          )

        assert_error ArgumentError, expected_msg, fn -> :re.run("x", "é(", [:unicode]) end
      end

      test "raises ArgumentError on invalid UTF-8 after a UTF pattern verb" do
        expected_msg =
          build_argument_error_msg(
            2,
            "could not parse regular expression\nUTF-8 error: illegal byte (0xfe or 0xff) on character 6"
          )

        assert_error ArgumentError, expected_msg, fn ->
          :re.run("x", ["(*UTF)" | <<255>>], [])
        end
      end

      test "raises ArgumentError on invalid option" do
        assert_error ArgumentError,
                     build_argument_error_msg(3, "invalid options"),
                     fn -> :re.run("x", "a", [:bad]) end
      end

      test "raises ArgumentError on non-list options" do
        assert_error ArgumentError,
                     build_argument_error_msg(3, "invalid options"),
                     fn -> :re.run("x", "a", :bad) end
      end

      test "raises ArgumentError on improper options list" do
        assert_error ArgumentError,
                     build_argument_error_msg(3, "invalid options"),
                     fn -> :re.run("x", "a", [:anchored | :bad]) end
      end

      test "combines subject and pattern errors" do
        expected_msg = """
        errors were found at the given arguments:

          * 1st argument: not an iodata term
          * 2nd argument: neither an iodata term nor a compiled regular expression
        """

        assert_error ArgumentError, expected_msg, fn -> :re.run(:a, :b, []) end
      end

      test "combines pattern and options errors" do
        expected_msg = """
        errors were found at the given arguments:

          * 2nd argument: could not parse regular expression
        numbers out of order in {} quantifier on character 5
          * 3rd argument: invalid options
        """

        assert_error ArgumentError, expected_msg, fn -> :re.run("x", "a{2,1}", [:bad]) end
      end

      test "combines subject and options errors" do
        expected_msg = """
        errors were found at the given arguments:

          * 1st argument: not an iodata term
          * 3rd argument: invalid options
        """

        assert_error ArgumentError, expected_msg, fn -> :re.run(:a, "ok", [:bad]) end
      end

      test "combines subject, pattern and options errors" do
        expected_msg = """
        errors were found at the given arguments:

          * 1st argument: not an iodata term
          * 2nd argument: neither an iodata term nor a compiled regular expression
          * 3rd argument: invalid options
        """

        assert_error ArgumentError, expected_msg, fn -> :re.run(:a, :b, [:bad]) end
      end

      test "combines pattern shape and options errors with the unicode option" do
        expected_msg = """
        errors were found at the given arguments:

          * 2nd argument: neither an iodata term nor a compiled regular expression
          * 3rd argument: invalid options
        """

        assert_error ArgumentError, expected_msg, fn ->
          :re.run("x", :foo, [:unicode, :bad])
        end
      end

      test "subject error wins over compile option error with a compiled pattern" do
        {:ok, compiled} = :re.compile("b")

        assert_error ArgumentError,
                     build_argument_error_msg(1, "not an iodata term"),
                     fn -> :re.run(:abc, compiled, [:caseless]) end
      end

      test "options error wins over unicode conversion errors" do
        assert_error ArgumentError,
                     build_argument_error_msg(3, "invalid options"),
                     fn -> :re.run("x", <<255>>, [:unicode, :bad]) end
      end

      test "raises plain ArgumentError on compile option with a compiled pattern" do
        {:ok, compiled} = :re.compile("b")

        assert_error ArgumentError, "argument error", fn ->
          :re.run("x", compiled, [:caseless])
        end
      end

      test "raises plain ArgumentError on unicode option with a compiled pattern" do
        {:ok, compiled} = :re.compile("b")

        assert_error ArgumentError, "argument error", fn ->
          :re.run("x", compiled, [:unicode])
        end
      end

      test "raises plain ArgumentError on invalid UTF-8 pattern with the unicode option" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run("x", <<255>>, [:unicode])
        end
      end

      test "raises plain ArgumentError on invalid pattern char data with the unicode option" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run("x", [:bad], [:unicode])
        end
      end

      test "raises plain ArgumentError on surrogate pattern code point with the unicode option" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run("x", [0xD800], [:unicode])
        end
      end

      test "raises plain ArgumentError on never_utf and unicode option clash" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run("x", "a", [:unicode, :never_utf])
        end
      end

      test "raises plain ArgumentError on UTF pattern verb with never_utf option" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run("x", "(*UTF)a", [:never_utf])
        end
      end

      test "raises plain ArgumentError on bad subject with parse error and unicode option" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run(:abc, "a{2,1}", [:unicode])
        end
      end

      test "raises plain ArgumentError on non-chardata subject with the unicode option" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run(:abc, "a", [:unicode])
        end
      end

      test "raises plain ArgumentError on surrogate subject code point with the unicode option" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run([0xD800], "a", [:unicode])
        end
      end

      test "raises plain ArgumentError on invalid UTF-8 subject with a unicode compiled pattern" do
        {:ok, compiled} = :re.compile("é", [:unicode])

        assert_error ArgumentError, "argument error", fn ->
          :re.run(<<255, "ab">>, compiled, [])
        end
      end

      test "raises plain ArgumentError on non-iodata subject with a unicode compiled pattern" do
        {:ok, compiled} = :re.compile("é", [:unicode])

        assert_error ArgumentError, "argument error", fn ->
          :re.run(:abc, compiled, [])
        end
      end

      test "raises plain ArgumentError on invalid UTF-8 subject with a UTF verb pattern" do
        assert_error ArgumentError, "argument error", fn ->
          :re.run(<<255>>, "(*UTF)é", [])
        end
      end
    end
  end

  describe "version/0" do
    test "returns supported PCRE version" do
      assert :re.version() =~ ~r/^\d+\.\d+ \d{4}-\d{2}-\d{2}$/
    end
  end
end
