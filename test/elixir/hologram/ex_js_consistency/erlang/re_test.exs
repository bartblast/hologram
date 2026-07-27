defmodule Hologram.ExJsConsistency.Erlang.ReTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/re_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

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
      expected_msg =
        build_multi_argument_error_msg([
          {1, "not an iodata term"},
          {2, "invalid options"}
        ])

      assert_error ArgumentError, expected_msg, fn -> :re.compile(:abc, [:bad]) end
    end
  end

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

  describe "run/2" do
    test "matches with default options" do
      assert :re.run("abbc", "b+") == {:match, [{1, 2}]}
    end

    test "returns nomatch without a match" do
      assert :re.run("x", "b+") == :nomatch
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

    test "caseless unicode matches a literal across a folding class" do
      # The subject is long s, which folds together with S and s
      assert :re.run("ſ", "s", [:caseless, :unicode]) == {:match, [{0, 2}]}
    end

    test "caseless unicode matches a literal across a folding class when interpreted" do
      # The subject is long s, which folds together with S and s
      assert :re.run("ſ", "(*LIMIT_MATCH=1000)s", [:caseless, :unicode]) == {:match, [{0, 2}]}
    end

    test "caseless unicode matches a range across a folding class" do
      # The subject is the Kelvin sign, which folds together with K and k
      assert :re.run("K", "[f-m]", [:caseless, :unicode]) == {:match, [{0, 3}]}
    end

    test "caseless unicode matches a range across a folding class when interpreted" do
      # The subject is the Kelvin sign, which folds together with K and k
      assert :re.run("K", "(*LIMIT_MATCH=1000)[f-m]", [:caseless, :unicode]) ==
               {:match, [{0, 3}]}
    end

    test "caseless unicode does not match a char that folds only to itself" do
      # The subject is dotless i, which neither I nor i folds to
      assert :re.run("ı", "I", [:caseless, :unicode]) == :nomatch
    end

    test "caseless unicode does not match a char that folds only to itself when interpreted" do
      # The subject is dotless i, which neither I nor i folds to
      assert :re.run("ı", "(*LIMIT_MATCH=1000)I", [:caseless, :unicode]) == :nomatch
    end

    test "caseless unicode matches a backreference across a folding class" do
      # The second subject char is the Kelvin sign, which folds together with K and k
      assert :re.run("kK", "(k)\\1", [:caseless, :unicode]) == {:match, [{0, 4}, {0, 1}]}
    end

    test "caseless unicode matches a backreference across a folding class when interpreted" do
      # The second subject char is the Kelvin sign, which folds together with K and k
      assert :re.run("kK", "(*LIMIT_MATCH=1000)(k)\\1", [:caseless, :unicode]) ==
               {:match, [{0, 4}, {0, 1}]}
    end

    test "caseless unicode keeps \\w fold-free" do
      # The subject is long s, which folds together with S and s
      assert :re.run("ſ", "\\w", [:caseless, :unicode]) == :nomatch
    end

    test "caseless unicode keeps a word boundary fold-free" do
      # The subject ends with long s, which folds together with S and s
      assert :re.run("aſ", "a\\b", [:caseless, :unicode]) == {:match, [{0, 1}]}
    end

    test "caseless unicode keeps a shorthand class member fold-free" do
      # The subject is long s, which folds together with S and s
      assert :re.run("ſ", "[\\w]", [:caseless, :unicode]) == :nomatch
    end

    test "caseless unicode keeps a POSIX class member fold-free" do
      # The subject is long s, which folds together with S and s
      assert :re.run("ſ", "[[:alpha:]]", [:caseless, :unicode]) == :nomatch
    end

    test "matches a literal digit after an atomic group" do
      assert :re.run("a1", "(?>a)1", []) == {:match, [{0, 2}]}
    end

    test "matches a literal digit after an atomic group when interpreted" do
      assert :re.run("a1", "(*LIMIT_MATCH=1000)(?>a)1", []) == {:match, [{0, 2}]}
    end

    test "matches a literal digit after a numeric backreference" do
      assert :re.run("aa1", "(a)\\g{1}1", []) == {:match, [{0, 3}, {0, 1}]}
    end

    test "matches a literal digit after a numeric backreference when interpreted" do
      assert :re.run("aa1", "(*LIMIT_MATCH=1000)(a)\\g{1}1", []) == {:match, [{0, 3}, {0, 1}]}
    end

    test "keeps \\K applied from inside an option scope" do
      assert :re.run("ab", "(?i)a\\Kb", []) == {:match, [{1, 1}]}
    end

    test "accepts the obsolete LIMIT_RECURSION limit verb" do
      assert :re.run("ab", "(*LIMIT_RECURSION=1000)a+b", []) == {:match, [{0, 2}]}
    end

    test "defaults the capture type to index" do
      assert :re.run("abbc", "a(b+)", [{:capture, :all}]) == {:match, [{0, 3}, {1, 2}]}
    end

    test "captures all with the binary type" do
      assert :re.run("abbc", "a(b+)", [{:capture, :all, :binary}]) == {:match, ["abb", "bb"]}
    end

    test "captures all with the list type" do
      assert :re.run("abbc", "a(b+)", [{:capture, :all, :list}]) ==
               {:match, [~c"abb", ~c"bb"]}
    end

    test "returns UTF-8 binaries with the binary type in unicode mode" do
      assert :re.run("aéb", "(éb)", [:unicode, {:capture, :all, :binary}]) ==
               {:match, ["éb", "éb"]}
    end

    test "returns raw bytes with the binary type in byte mode" do
      assert :re.run(<<97, 233>>, <<233>>, [{:capture, :all, :binary}]) == {:match, [<<233>>]}
    end

    test "returns code points with the list type in unicode mode" do
      assert :re.run("a😀", "(😀)", [:unicode, {:capture, :all, :list}]) ==
               {:match, [[128_512], [128_512]]}
    end

    test "returns bytes with the list type in byte mode" do
      assert :re.run(<<97, 233>>, <<233>>, [{:capture, :all, :list}]) == {:match, [[233]]}
    end

    test "captures only the full match with the first spec" do
      assert :re.run("abbc", "a(b+)", [{:capture, :first}]) == {:match, [{0, 3}]}
    end

    test "captures the full match binary with the first spec" do
      assert :re.run("abbc", "a(b+)", [{:capture, :first, :binary}]) == {:match, ["abb"]}
    end

    test "returns bare match with the none spec" do
      assert :re.run("abbc", "a(b+)", [{:capture, :none}]) == :match
    end

    test "returns bare match with the none spec and a type" do
      assert :re.run("abbc", "a(b+)", [{:capture, :none, :binary}]) == :match
    end

    test "captures only groups with the all_but_first spec" do
      assert :re.run("abc", "a(b)(c)", [{:capture, :all_but_first}]) ==
               {:match, [{1, 1}, {2, 1}]}
    end

    test "returns empty list with the all_but_first spec and no groups" do
      assert :re.run("abc", "b", [{:capture, :all_but_first}]) == {:match, []}
    end

    test "truncates trailing unset groups with the all_but_first spec" do
      assert :re.run("ab", "(a)(b)?(c)?", [{:capture, :all_but_first}]) ==
               {:match, [{0, 1}, {1, 1}]}
    end

    test "sorts names by byte order with the all_names spec" do
      assert :re.run("xy", "(?<b>x)(?<a>y)", [{:capture, :all_names}]) ==
               {:match, [{1, 1}, {0, 1}]}
    end

    test "keeps trailing unset names with the all_names spec" do
      assert :re.run("x", "(?<a>x)(?<b>z)?", [{:capture, :all_names}]) ==
               {:match, [{0, 1}, {-1, 0}]}
    end

    test "returns bare match with the all_names spec and no named groups" do
      assert :re.run("ab", "a(b)", [{:capture, :all_names}]) == :match
    end

    test "collapses duplicate names to the first set group with the all_names spec" do
      assert :re.run("b", "(?<n>a)?(?<n>b)?", [:dupnames, {:capture, :all_names}]) ==
               {:match, [{0, 1}]}
    end

    test "captures listed group indices in the given order" do
      assert :re.run("ab", "(a)(b)", [{:capture, [2, 0]}]) == {:match, [{1, 1}, {0, 2}]}
    end

    test "treats an out-of-range group index as unset" do
      assert :re.run("ab", "(a)", [{:capture, [5]}]) == {:match, [{-1, 0}]}
    end

    test "treats the maximum group index as unset" do
      assert :re.run("ab", "(a)", [{:capture, [2_147_483_647]}]) == {:match, [{-1, 0}]}
    end

    test "resolves an atom group name" do
      assert :re.run("abbc", "(?<foo>b+)", [{:capture, [:foo]}]) == {:match, [{1, 2}]}
    end

    test "resolves a binary group name" do
      assert :re.run("abbc", "(?<foo>b+)", [{:capture, ["foo"]}]) == {:match, [{1, 2}]}
    end

    test "resolves a charlist group name" do
      assert :re.run("abbc", "(?<foo>b+)", [{:capture, [~c"foo"]}]) == {:match, [{1, 2}]}
    end

    test "resolves a nested chardata group name" do
      assert :re.run("abbc", "(?<foo>b+)", [{:capture, [["f", [111, "o"]]]}]) ==
               {:match, [{1, 2}]}
    end

    test "treats an unknown group name as unset" do
      assert :re.run("abbc", "(?<foo>b+)", [{:capture, [:bar], :binary}]) == {:match, [""]}
    end

    test "treats an invalid UTF-8 binary name as unset" do
      assert :re.run("abbc", "(?<foo>b+)", [{:capture, [<<255>>], :binary}]) == {:match, [""]}
    end

    test "resolves a duplicate name to the first set group" do
      assert :re.run("b", "(?<n>a)?(?<n>b)?", [:dupnames, {:capture, [:n]}]) ==
               {:match, [{0, 1}]}
    end

    test "returns bare match with an empty capture list" do
      assert :re.run("abbc", "a(b+)", [{:capture, []}]) == :match
    end

    test "keeps trailing unset groups with a capture list" do
      assert :re.run("a", "(a)(b)?", [{:capture, [1, 2]}]) == {:match, [{0, 1}, {-1, 0}]}
    end

    test "returns nomatch with a capture spec" do
      assert :re.run("z", "a", [{:capture, :first, :binary}]) == :nomatch
    end

    test "uses the last capture option" do
      assert :re.run("a", "a", [{:capture, :none}, {:capture, :first}]) == {:match, [{0, 1}]}
    end

    test "applies the capture spec to a compiled pattern" do
      {:ok, compiled} = :re.compile("a(b+)")

      assert :re.run("abbc", compiled, [{:capture, :all_but_first, :binary}]) ==
               {:match, ["bb"]}
    end

    test "starts matching at the offset" do
      assert :re.run("abab", "ab", [{:offset, 1}]) == {:match, [{2, 2}]}
    end

    test "matches an empty pattern at the end offset" do
      assert :re.run("ab", "", [{:offset, 2}]) == {:match, [{2, 0}]}
    end

    test "uses the last offset option" do
      assert :re.run("aba", "a", [{:offset, 1}, {:offset, 0}]) == {:match, [{0, 1}]}
    end

    test "^ doesn't match at the offset" do
      assert :re.run("ab", "^b", [{:offset, 1}]) == :nomatch
    end

    test "^ matches after a newline before the offset with multiline" do
      assert :re.run("ab\ncd", "^c", [{:offset, 3}, :multiline]) == {:match, [{3, 1}]}
    end

    test "\\A doesn't match at the offset" do
      assert :re.run("aa", "\\Aa", [{:offset, 1}]) == :nomatch
    end

    test "\\G matches at the offset" do
      assert :re.run("aba", "\\Ga", [{:offset, 2}]) == {:match, [{2, 1}]}
    end

    test "a lookbehind sees before the offset" do
      assert :re.run("ab", "(?<=a)b", [{:offset, 1}]) == {:match, [{1, 1}]}
    end

    test "offset counts bytes in unicode mode" do
      assert :re.run("éb", "b", [:unicode, {:offset, 2}]) == {:match, [{2, 1}]}
    end

    test "anchored pins the match to the offset" do
      assert :re.run("abb", "b", [:anchored, {:offset, 1}]) == {:match, [{1, 1}]}
    end

    test "notbol makes ^ fail at the subject start" do
      assert :re.run("ab", "^a", [:notbol]) == :nomatch
    end

    test "notbol keeps ^ matching after an internal newline" do
      assert :re.run("a\nb", "^b", [:multiline, :notbol]) == {:match, [{2, 1}]}
    end

    test "notbol doesn't affect \\A" do
      assert :re.run("ab", "\\Aa", [:notbol]) == {:match, [{0, 1}]}
    end

    test "notbol works with a compiled pattern" do
      {:ok, compiled} = :re.compile("^a")

      assert :re.run("ab", compiled, [:notbol]) == :nomatch
    end

    test "noteol makes $ fail at the subject end" do
      assert :re.run("ab", "b$", [:noteol]) == :nomatch
    end

    test "noteol makes $ fail before a final newline" do
      assert :re.run("ab\n", "b$", [:noteol]) == :nomatch
    end

    test "noteol keeps $ matching before an internal newline" do
      assert :re.run("a\nb", "a$", [:multiline, :noteol]) == {:match, [{0, 1}]}
    end

    test "noteol doesn't affect \\z" do
      assert :re.run("ab", "b\\z", [:noteol]) == {:match, [{1, 1}]}
    end

    test "multiline $ matches between CR and LF under the anycrlf convention" do
      assert :re.run("a\r\nb", "\\r$", [:multiline, {:newline, :anycrlf}]) == {:match, [{1, 1}]}
    end

    test "multiline $ matches between CR and LF under the anycrlf convention when interpreted" do
      assert :re.run("a\r\nb", "(*LIMIT_MATCH=1000)\\r$", [:multiline, {:newline, :anycrlf}]) ==
               {:match, [{1, 1}]}
    end

    test "multiline $ does not match between CR and LF under the crlf convention" do
      assert :re.run("a\r\nb", "\\r$", [:multiline, {:newline, :crlf}]) == :nomatch
    end

    test "multiline $ does not match between CR and LF under the crlf convention when interpreted" do
      assert :re.run("a\r\nb", "(*LIMIT_MATCH=1000)\\r$", [:multiline, {:newline, :crlf}]) ==
               :nomatch
    end

    test "notempty backtracks to a non-empty match" do
      assert :re.run("a", "|a", [:notempty]) == {:match, [{0, 1}]}
    end

    test "notempty rejects empty matches at every position" do
      assert :re.run("b", "a*", [:notempty]) == :nomatch
    end

    test "notempty scans past rejected empty matches" do
      assert :re.run("ba", "a*", [:notempty]) == {:match, [{1, 1}]}
    end

    test "notempty_atstart rejects an empty match at the start position" do
      assert :re.run("ba", "a*", [:notempty_atstart]) == {:match, [{1, 1}]}
    end

    test "notempty_atstart allows an empty match past the offset" do
      assert :re.run("ba", "b*", [:notempty_atstart, {:offset, 1}]) == {:match, [{2, 0}]}
    end

    test "firstline rejects a match past the first newline" do
      assert :re.run("a\nb", "b", [:firstline]) == :nomatch
    end

    test "firstline allows a match before the first newline" do
      assert :re.run("ab\ncd", "b", [:firstline]) == {:match, [{1, 1}]}
    end

    test "firstline allows a match crossing the first newline" do
      assert :re.run("ab\ncd", "b\\nc", [:firstline]) == {:match, [{1, 3}]}
    end

    test "firstline uses the newline convention" do
      assert :re.run("a\rb", "b", [:firstline, {:newline, :anycrlf}]) == :nomatch
    end

    test "firstline counts newlines from the offset" do
      assert :re.run("a\nb", "b", [:firstline, {:offset, 2}]) == {:match, [{2, 1}]}
    end

    test "compile-time firstline pattern applies when running" do
      {:ok, compiled} = :re.compile("b", [:firstline])

      assert :re.run("a\nb", compiled, []) == :nomatch
    end

    test "global collects successive matches" do
      assert :re.run("abab", "a", [:global]) == {:match, [[{0, 1}], [{2, 1}]]}
    end

    test "global collects captures per match" do
      assert :re.run("abab", "a(b)", [:global]) ==
               {:match, [[{0, 2}, {1, 1}], [{2, 2}, {3, 1}]]}
    end

    test "global truncates trailing unset groups per match" do
      assert :re.run("aba", "a(b)?", [:global]) == {:match, [[{0, 2}, {1, 1}], [{2, 1}]]}
    end

    test "global advances past an empty match" do
      assert :re.run("ab", "a*", [:global]) == {:match, [[{0, 1}], [{1, 0}], [{2, 0}]]}
    end

    test "global reports a successful anchored retry after an empty match" do
      assert :re.run("a", "|a", [:global]) == {:match, [[{0, 0}], [{0, 1}], [{1, 0}]]}
    end

    test "global matches once on an empty subject" do
      assert :re.run("", "", [:global]) == {:match, [[{0, 0}]]}
    end

    test "global continues at the previous match end" do
      assert :re.run("abab", "a\\Kb", [:global]) == {:match, [[{1, 1}], [{3, 1}]]}
    end

    test "global advances over a CRLF pair as one newline" do
      assert :re.run("\r\n", "", [:global, {:newline, :crlf}]) == {:match, [[{0, 0}], [{2, 0}]]}
    end

    test "global advances over a whole character in unicode mode" do
      assert :re.run("😀", "x*", [:global, :unicode]) == {:match, [[{0, 0}], [{4, 0}]]}
    end

    test "global starts at the offset" do
      assert :re.run("abab", "a", [:global, {:offset, 1}]) == {:match, [[{2, 1}]]}
    end

    test "global returns nomatch on offset beyond the subject" do
      assert :re.run("ab", "a", [:global, {:offset, 5}]) == :nomatch
    end

    test "global returns nomatch on unicode offset beyond the subject" do
      assert :re.run("éb", "b", [:global, :unicode, {:offset, 9}]) == :nomatch
    end

    test "global anchored continues while matches are adjacent" do
      assert :re.run("aab", "a", [:anchored, :global]) == {:match, [[{0, 1}], [{1, 1}]]}
    end

    test "global anchored stops at the first failed position" do
      assert :re.run("aba", "a", [:anchored, :global]) == {:match, [[{0, 1}]]}
    end

    test "global applies scan flags to every attempt" do
      assert :re.run("ab", "a*", [:global, :notempty]) == {:match, [[{0, 1}]]}
    end

    test "global returns nomatch without a match" do
      assert :re.run("ab", "x", [:global]) == :nomatch
    end

    test "global shapes binary captures per match" do
      assert :re.run("abab", "a(b)", [:global, {:capture, :all_but_first, :binary}]) ==
               {:match, [["b"], ["b"]]}
    end

    test "global returns bare match with the none spec" do
      assert :re.run("aa", "a", [:global, {:capture, :none}]) == :match
    end

    test "global works with a compiled pattern" do
      {:ok, compiled} = :re.compile("a")

      assert :re.run("aba", compiled, [:global]) == {:match, [[{0, 1}], [{2, 1}]]}
    end

    test "an exceeded match limit reports nomatch" do
      assert :re.run("a", "a", [{:match_limit, 0}]) == :nomatch
    end

    test "matches within the match limit" do
      assert :re.run("a", "a", [{:match_limit, 100}]) == {:match, [{0, 1}]}
    end

    test "the match limit stops runaway backtracking" do
      assert :re.run("aaaaaaaaaax", "(a+)+b", [{:match_limit, 1}]) == :nomatch
    end

    test "an exceeded recursion limit reports nomatch" do
      assert :re.run("a", "a", [{:match_limit_recursion, 0}]) == :nomatch
    end

    test "matches within the recursion limit" do
      assert :re.run("a", "a", [{:match_limit_recursion, 100}]) == {:match, [{0, 1}]}
    end

    test "match limit works with a compiled pattern" do
      {:ok, compiled} = :re.compile("(a+)+b")

      assert :re.run("aaaaaaaaaax", compiled, [{:match_limit, 1}]) == :nomatch
    end

    test "uses the last match limit option" do
      assert :re.run("a", "a", [{:match_limit, 0}, {:match_limit, 100}]) == {:match, [{0, 1}]}
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
      expected_msg =
        build_multi_argument_error_msg([
          {1, "not an iodata term"},
          {2, "neither an iodata term nor a compiled regular expression"}
        ])

      assert_error ArgumentError, expected_msg, fn -> :re.run(:a, :b, []) end
    end

    test "combines pattern and options errors" do
      expected_msg =
        build_multi_argument_error_msg([
          {2,
           "could not parse regular expression\nnumbers out of order in {} quantifier on character 5"},
          {3, "invalid options"}
        ])

      assert_error ArgumentError, expected_msg, fn -> :re.run("x", "a{2,1}", [:bad]) end
    end

    test "combines subject and options errors" do
      expected_msg =
        build_multi_argument_error_msg([
          {1, "not an iodata term"},
          {3, "invalid options"}
        ])

      assert_error ArgumentError, expected_msg, fn -> :re.run(:a, "ok", [:bad]) end
    end

    test "combines subject, pattern and options errors" do
      expected_msg =
        build_multi_argument_error_msg([
          {1, "not an iodata term"},
          {2, "neither an iodata term nor a compiled regular expression"},
          {3, "invalid options"}
        ])

      assert_error ArgumentError, expected_msg, fn -> :re.run(:a, :b, [:bad]) end
    end

    test "combines pattern shape and options errors with the unicode option" do
      expected_msg =
        build_multi_argument_error_msg([
          {2, "neither an iodata term nor a compiled regular expression"},
          {3, "invalid options"}
        ])

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

    test "raises plain ArgumentError on invalid capture spec atom" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, :bogus}])
      end
    end

    test "raises plain ArgumentError on non-list capture spec" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, 1}])
      end
    end

    test "raises plain ArgumentError on improper capture spec list" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, [0 | 1]}])
      end
    end

    test "raises plain ArgumentError on invalid capture type" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, :all, :bogus}])
      end
    end

    test "raises plain ArgumentError on non-atom capture type" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, :all, 5}])
      end
    end

    test "raises plain ArgumentError on invalid capture type with the none spec" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, :none, :bogus}])
      end
    end

    test "raises plain ArgumentError on negative group index" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, [-1]}])
      end
    end

    test "raises plain ArgumentError on group index above the 32-bit range" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, [2_147_483_648]}])
      end
    end

    test "raises plain ArgumentError on float capture spec element" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, [1.5]}])
      end
    end

    test "raises plain ArgumentError on non-binary bitstring capture spec element" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, [<<1::1>>]}])
      end
    end

    test "raises plain ArgumentError on invalid code point in a name" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, [[99_999_999]]}])
      end
    end

    test "raises plain ArgumentError on improper name charlist" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("a", "a", [{:capture, [[102 | 111]]}])
      end
    end

    test "raises plain ArgumentError on invalid capture spec without a match" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("z", "a", [{:capture, :bogus}])
      end
    end

    test "raises ArgumentError on capture option with extra elements" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("a", "a", [{:capture, :all, :index, :extra}]) end
    end

    test "subject error wins over capture spec error" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an iodata term"),
                   fn -> :re.run(:x, "a", [{:capture, :bogus}]) end
    end

    test "unicode pattern error wins over capture spec error" do
      expected_msg =
        build_argument_error_msg(
          2,
          "could not parse regular expression\nmissing closing parenthesis on character 1"
        )

      assert_error ArgumentError, expected_msg, fn ->
        :re.run("x", "(", [:unicode, {:capture, :bogus}])
      end
    end

    test "raises ArgumentError on negative offset" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("ab", "a", [{:offset, -1}]) end
    end

    test "raises ArgumentError on non-integer offset" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("ab", "a", [{:offset, :x}]) end
    end

    test "raises ArgumentError on offset above the 32-bit range" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("ab", "a", [{:offset, 2_147_483_648}]) end
    end

    test "raises ArgumentError on offset tuple with extra elements" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("ab", "a", [{:offset, 1, 2}]) end
    end

    test "raises plain ArgumentError on offset beyond the subject" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("ab", "a", [{:offset, 3}])
      end
    end

    test "raises plain ArgumentError on maximum offset beyond the subject" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("ab", "a", [{:offset, 2_147_483_647}])
      end
    end

    test "raises plain ArgumentError on offset inside a character" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("éb", "b", [:unicode, {:offset, 1}])
      end
    end

    test "raises plain ArgumentError on firstline with a compiled pattern" do
      {:ok, compiled} = :re.compile("b")

      assert_error ArgumentError, "argument error", fn ->
        :re.run("a\nb", compiled, [:firstline])
      end
    end

    test "raises plain ArgumentError on offset inside a character with global" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("éb", "b", [:global, :unicode, {:offset, 1}])
      end
    end

    test "capture spec error wins over global nomatch" do
      assert_error ArgumentError, "argument error", fn ->
        :re.run("ab", "a", [:global, {:offset, 5}, {:capture, :bogus}])
      end
    end

    test "raises ArgumentError on negative match limit" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("a", "a", [{:match_limit, -1}]) end
    end

    test "raises ArgumentError on non-integer match limit" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("a", "a", [{:match_limit, :x}]) end
    end

    test "raises ArgumentError on match limit above the 32-bit range" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("a", "a", [{:match_limit, 2_147_483_648}]) end
    end

    test "raises ArgumentError on match limit recursion above the 32-bit range" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("a", "a", [{:match_limit_recursion, 2_147_483_648}]) end
    end

    test "raises ArgumentError on match limit tuple with extra elements" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("a", "a", [{:match_limit, 1, 2}]) end
    end

    test "raises plain ArgumentError on newline option with a compiled pattern" do
      {:ok, compiled} = :re.compile("a.b")

      assert_error ArgumentError, "argument error", fn ->
        :re.run("a\rb", compiled, [{:newline, :cr}])
      end
    end

    test "raises plain ArgumentError on bsr option with a compiled pattern" do
      {:ok, compiled} = :re.compile("a\\Rb")

      assert_error ArgumentError, "argument error", fn ->
        :re.run("a\vb", compiled, [:bsr_anycrlf])
      end
    end

    test "raises ArgumentError on invalid newline type with a compiled pattern" do
      {:ok, compiled} = :re.compile("a")

      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :re.run("a", compiled, [{:newline, :bogus}]) end
    end
  end

  describe "version/0" do
    test "returns supported PCRE version" do
      assert :re.version() =~ ~r/^\d+\.\d+ \d{4}-\d{2}-\d{2}$/
    end
  end
end
