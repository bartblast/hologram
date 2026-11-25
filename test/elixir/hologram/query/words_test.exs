defmodule Hologram.Query.WordsTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Words

  describe "backfill_only_hint/1" do
    test "names a word the expression calls" do
      assert backfill_only_hint(quote(do: coalesce(a, "x"))) ==
               " - if you meant the query word coalesce, it works only in a migration's backfill: for now"
    end

    test "finds a word inside a pipe" do
      piped = Code.string_to_quoted!(~s[split(a, " ") |> at(0)])

      assert backfill_only_hint(piped) ==
               " - if you meant the query word split, it works only in a migration's backfill: for now"
    end

    test "is empty when the expression calls no word" do
      assert backfill_only_hint(quote(do: name(a))) == ""
    end

    test "is empty for a variable named like a word" do
      assert backfill_only_hint(quote(do: at)) == ""
    end

    test "is empty for a call of another module named like a word" do
      assert backfill_only_hint(quote(do: String.split(a, " "))) == ""
    end

    test "is empty for a word inside a pin, which is the surrounding code's" do
      assert backfill_only_hint(quote(do: foo(^split(a, " ")))) == ""
    end

    test "is empty for a module attribute named like a word, which is the surrounding code's" do
      assert backfill_only_hint(Code.string_to_quoted!("foo(@split(a))")) == ""
    end

    test "is empty for a word a quote holds as data" do
      assert backfill_only_hint(Code.string_to_quoted!(~s[foo(quote(do: split(a, " ")))])) == ""
    end

    test "finds a word a quote unquotes" do
      ast = Code.string_to_quoted!(~s[foo(quote(do: bar(unquote(split(a, " ")))))])

      assert backfill_only_hint(ast) ==
               " - if you meant the query word split, it works only in a migration's backfill: for now"
    end

    test "is empty for an unquote a quote with unquote: false holds as data" do
      ast = Code.string_to_quoted!(~s[foo(quote(unquote: false, do: unquote(split(a, " "))))])

      assert backfill_only_hint(ast) == ""
    end

    test "is empty for an unquote a quote with bind_quoted: holds as data" do
      ast =
        Code.string_to_quoted!(~s|foo(quote(bind_quoted: [x: 1], do: unquote(split(a, " "))))|)

      assert backfill_only_hint(ast) == ""
    end

    test "is empty for an unquote in the body of a nested quote" do
      ast = Code.string_to_quoted!(~s[foo(quote(do: quote(do: unquote(split(a, " ")))))])

      assert backfill_only_hint(ast) == ""
    end

    test "finds a word unquoted in the separate options of a nested quote" do
      ast =
        Code.string_to_quoted!(
          ~s|foo(quote(do: quote([bind_quoted: [x: unquote(split(a, " "))]], do: x)))|
        )

      assert backfill_only_hint(ast) ==
               " - if you meant the query word split, it works only in a migration's backfill: for now"
    end

    test "finds a word a nested quote's separate options unquote whole" do
      ast = Code.string_to_quoted!(~s[foo(quote(do: quote(unquote(split(a, " ")), do: 1)))])

      assert backfill_only_hint(ast) ==
               " - if you meant the query word split, it works only in a migration's backfill: for now"
    end

    test "is empty for a word piped into an unquote, which a quote holds as data" do
      ast = Code.string_to_quoted!(~s[foo(quote(do: split(a, " ") |> unquote()))])

      assert backfill_only_hint(ast) == ""
    end

    test "is empty for a word in a body piped into a quote" do
      for source <- [
            ~s{foo([do: split(a, " ")] |> quote())},
            ~s{foo([] |> quote(do: split(a, " ")))},
            ~s{foo(Kernel.|>([do: split(a, " ")], quote()))},
            ~s{foo(Kernel.|>([], quote(do: split(a, " "))))}
          ] do
        assert backfill_only_hint(Code.string_to_quoted!(source)) == ""
      end
    end

    test "finds a word in the options piped into a quote" do
      for source <- [
            ~s{foo([bind_quoted: [x: at(a, 0)]] |> quote(do: x))},
            ~s{foo(Kernel.|>([bind_quoted: [x: at(a, 0)]], quote(do: x)))}
          ] do
        assert backfill_only_hint(Code.string_to_quoted!(source)) ==
                 " - if you meant the query word at, it works only in a migration's backfill: for now"
      end
    end

    test "finds a word unquoted as the name of a remote call" do
      ast = Code.string_to_quoted!(~s[foo(quote(do: String.unquote(split(a, " "))(b)))])

      assert backfill_only_hint(ast) ==
               " - if you meant the query word split, it works only in a migration's backfill: for now"
    end

    test "finds a word unquoted as the receiver of a remote call" do
      ast = Code.string_to_quoted!(~s[foo(quote(do: unquote(split(a, " ")).unquote(b)(c)))])

      assert backfill_only_hint(ast) ==
               " - if you meant the query word split, it works only in a migration's backfill: for now"
    end

    test "finds a word in the options of a quote" do
      ast = Code.string_to_quoted!(~s|foo(quote(bind_quoted: [x: at(a, 0)], do: x))|)

      assert backfill_only_hint(ast) ==
               " - if you meant the query word at, it works only in a migration's backfill: for now"
    end
  end

  describe "add_backfill_only_hint/2" do
    test "adds the hint to the error's message" do
      error = %Hologram.CompileError{message: "refused"}

      assert add_backfill_only_hint(error, quote(do: split(a, " "))).message ==
               "refused - if you meant the query word split, it works only in a migration's backfill: for now"
    end

    test "leaves a message that carries a hint already" do
      message =
        "refused - if you meant the query word at, it works only in a migration's backfill: for now"

      error = %Hologram.CompileError{message: message}

      assert add_backfill_only_hint(error, quote(do: split(a, " "))).message == message
    end

    test "leaves the message when the expression calls no word" do
      error = %Hologram.CompileError{message: "refused"}

      assert add_backfill_only_hint(error, quote(do: name(a))).message == "refused"
    end
  end

  describe "at/2" do
    test "counts from 0" do
      assert at(["a", "b"], 0) == "a"
      assert at(["a", "b"], 1) == "b"
    end

    test "gives nil past the end" do
      assert at(["a"], 1) == nil
    end

    test "gives nil for a nil list" do
      assert at(nil, 0) == nil
    end
  end

  describe "coalesce/1" do
    test "gives the first value that isn't nil" do
      assert coalesce([nil, "a", "b"]) == "a"
    end

    test "gives nil when all are nil" do
      assert coalesce([nil, nil]) == nil
    end

    test "takes false as a value" do
      assert coalesce([nil, false, true]) == false
    end

    test "takes an empty string as a value" do
      assert coalesce(["", "a"]) == ""
    end

    test "reads no value past the one it gives" do
      values = Stream.map([nil, "a", :unread], &if(&1 == :unread, do: raise("read"), else: &1))

      assert coalesce(values) == "a"
    end
  end

  describe "concat/1" do
    test "joins strings" do
      assert concat(["a", " ", "b"]) == "a b"
    end

    test "gives nil when any operand is nil" do
      assert concat(["a", nil, "b"]) == nil
    end

    test "keeps empty strings" do
      assert concat(["", "a"]) == "a"
    end
  end

  describe "count/1" do
    test "counts rows" do
      assert count([%{}, %{}]) == 2
    end

    test "gives 0 for no rows" do
      assert count([]) == 0
    end
  end

  describe "most_common/2" do
    test "gives the most frequent value" do
      assert most_common(["a", "b", "b"]) == "b"
    end

    test "skips nil" do
      assert most_common([nil, nil, "a"]) == "a"
    end

    test "gives nil over no values" do
      assert most_common([]) == nil
    end

    test "gives nil when every value is nil" do
      assert most_common([nil, nil]) == nil
    end

    test "gives a tie to the smallest in sort order, not byte order" do
      assert most_common(["Zebra", "apple"]) == "apple"
    end

    test "keeps strings differing only in case apart" do
      assert most_common(["apple", "apple", "Apple"]) == "apple"
    end

    test "settles a tie on equal sort keys by the value" do
      assert most_common(["apple", "Apple"]) == "Apple"
    end

    test "orders an enum tie by its declared position" do
      assert most_common([:b, :a], %{b: 0, a: 1}) == :b
    end

    test "groups integers" do
      assert most_common([3, 1, 3, 2]) == 3
    end

    test "gives an integer tie to the smallest" do
      assert most_common([2, 1]) == 1
    end

    test "groups booleans" do
      assert most_common([true, false, true]) == true
    end

    test "gives a boolean tie to false" do
      assert most_common([true, false]) == false
    end

    test "orders dates chronologically across a year boundary" do
      assert most_common([~D[2026-01-01], ~D[2025-12-31]]) == ~D[2025-12-31]
    end

    test "groups datetimes equal at different precisions" do
      assert most_common([
               ~U[2026-01-01 00:00:00Z],
               ~U[2026-01-01 00:00:00.000Z],
               ~U[2025-01-01 00:00:00Z]
             ]) == ~U[2026-01-01 00:00:00Z]
    end

    test "groups times" do
      assert most_common([~T[10:00:00], ~T[09:00:00], ~T[10:00:00]]) == ~T[10:00:00]
    end
  end

  describe "split/2" do
    test "splits as String.split/2" do
      assert split("a, b", ", ") == ["a", "b"]
    end

    test "keeps empty parts at either end" do
      assert split(",a,", ",") == ["", "a", ""]
    end

    test "gives the whole text when the separator is absent" do
      assert split("a", ",") == ["a"]
    end

    test "gives one empty part for an empty string" do
      assert split("", ",") == [""]
    end

    test "gives nil for nil" do
      assert split(nil, ",") == nil
    end
  end
end
