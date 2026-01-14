defmodule Hologram.ExJsConsistency.Erlang.FilenameTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/filename_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "basename/1" do
    test "path with multiple segments" do
      assert :filename.basename("path/to/file.txt") == "file.txt"
    end

    test "path with single segment" do
      assert :filename.basename("file.txt") == "file.txt"
    end

    test "path with absolute path" do
      assert :filename.basename("/absolute/path/to/file.txt") == "file.txt"
    end

    test "path ending with slash" do
      assert :filename.basename("path/to/dir/") == "dir"
    end

    test "root path" do
      assert :filename.basename("/") == ""
    end

    test "empty string" do
      assert :filename.basename("") == ""
    end

    test "path with multiple consecutive slashes" do
      assert :filename.basename("path//to//file.txt") == "file.txt"
    end

    test "path with only slashes" do
      assert :filename.basename("///") == ""
    end

    test "bitstring input" do
      assert :filename.basename("path/to/file.txt") == "file.txt"
    end

    test "binary with invalid UTF-8 bytes" do
      # <<0xFF, 0xFE>> is invalid UTF-8
      filename = <<"path/to/", 0xFF, 0xFE, ".txt">>

      # Should preserve raw bytes for the invalid UTF-8
      expected = <<0xFF, 0xFE, ".", "t", "x", "t">>

      assert :filename.basename(filename) == expected
    end

    test "atom input" do
      assert :filename.basename(:"path/to/file.txt") == ~c"file.txt"
    end

    test "empty list input" do
      assert :filename.basename([]) == []
    end

    test "non-empty iolist input" do
      assert :filename.basename([~c"path/to/", ?f, ?i, ?l, ?e, ~c".txt"]) == ~c"file.txt"
    end

    test "iolist with invalid UTF-8 bytes" do
      # Pure charlist: [112, 97, 116, 104, 47, 116, 111, 47, 0xFF, 0xFE, 46, 116, 120, 116]
      # "path/to/" + [0xFF, 0xFE] + ".txt"
      filename = [?p, ?a, ?t, ?h, ?/, ?t, ?o, ?/, 0xFF, 0xFE, ?., ?t, ?x, ?t]

      # Should return raw bytes as integers: [0xFF, 0xFE, ?., ?t, ?x, ?t]
      expected = [0xFF, 0xFE, ?., ?t, ?x, ?t]

      assert :filename.basename(filename) == expected
    end

    test "charlist with only slashes" do
      assert :filename.basename([?/, ?/, ?/]) == []
    end

    test "raises FunctionClauseError if the argument is not a bitstring or atom or list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.basename(123) end
    end

    test "raises FunctionClauseError if the argument is a non-binary bitstring" do
      arg = <<1::1, 0::1, 1::1>>

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [arg, []]),
                   fn -> :filename.basename(arg) end
    end
  end

  describe "flatten/1" do
    test "binary" do
      filename = "path/to/file.txt"

      assert :filename.flatten(filename) == filename
    end

    test "atom" do
      assert :filename.flatten(:myfile) == ~c"myfile"
    end

    test "flat list of integers" do
      filename = [112, 97, 116, 104]

      assert :filename.flatten(filename) == filename
    end

    test "flat list of bitstrings" do
      filename = [<<"foo">>, <<"bar">>]

      assert :filename.flatten(filename) == filename
    end

    test "flat list of atoms" do
      # ?f = 102, ?o = 111, ?全 = 20840, ?息 = 24687, ?图 = 22270, ?b = 98, ?a = 97, ?r = 114
      assert :filename.flatten([:foo, :全息图, :bar]) == [
               102,
               111,
               111,
               20_840,
               24_687,
               22_270,
               98,
               97,
               114
             ]
    end

    test "nested list of integers" do
      assert :filename.flatten([112, [97, 116], 104]) == [112, 97, 116, 104]
    end

    test "deeply nested list of integers" do
      assert :filename.flatten([[[97, 98], 99], 100]) == [97, 98, 99, 100]
    end

    test "empty list" do
      assert :filename.flatten([]) == []
    end

    test "list with an empty list element" do
      assert :filename.flatten([97, [], 98]) == [97, 98]
    end

    test "mixed list with bitstrings, atoms, integers and nested lists" do
      # ?t = 116, ?o = 111
      assert :filename.flatten([<<"path">>, [47, :to], 63, [<<"file.txt">>]]) ==
               [<<"path">>, 47, 116, 111, 63, <<"file.txt">>]
    end

    test "raises FunctionClauseError if the argument is not a binary, atom, or list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.flatten(123) end
    end

    test "raises FunctionClauseError if the argument is a non-binary bitstring" do
      arg = <<1::1, 0::1, 1::1>>

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [arg, []]),
                   fn -> :filename.flatten(arg) end
    end
  end

  describe "split/1" do
    test "absolute Unix path" do
      assert :filename.split("/usr/local/bin") == ["/", "usr", "local", "bin"]
    end

    test "relative Unix path" do
      assert :filename.split("foo/bar") == ["foo", "bar"]
    end

    test "single component" do
      assert :filename.split("foo") == ["foo"]
    end

    test "root path" do
      assert :filename.split("/") == ["/"]
    end

    test "empty string" do
      assert :filename.split("") == []
    end

    test "multiple consecutive slashes" do
      assert :filename.split("//") == ["/"]
    end

    test "dot component" do
      assert :filename.split(".") == ["."]
    end

    test "double dot component" do
      assert :filename.split("..") == [".."]
    end

    test "path with dot in middle" do
      assert :filename.split("/./") == ["/", "."]
    end

    test "path with double dot in middle" do
      assert :filename.split("/../") == ["/", ".."]
    end

    test "relative path with dot prefix" do
      assert :filename.split("./foo") == [".", "foo"]
    end

    test "relative path with double dot prefix" do
      assert :filename.split("../foo") == ["..", "foo"]
    end

    test "path with dot in middle components" do
      assert :filename.split("foo/./bar") == ["foo", ".", "bar"]
    end

    test "path with double dot in middle components" do
      assert :filename.split("foo/../bar") == ["foo", "..", "bar"]
    end

    test "path with trailing slash" do
      assert :filename.split("foo/bar/") == ["foo", "bar"]
    end

    test "absolute path with trailing slash" do
      assert :filename.split("/foo/bar/") == ["/", "foo", "bar"]
    end

    test "path with multiple consecutive slashes in middle" do
      assert :filename.split("foo//bar") == ["foo", "bar"]
    end

    test "drive letter with colon and forward slash" do
      assert :filename.split("a:/msdev/include") == ["a:", "msdev", "include"]
    end

    test "charlist input" do
      assert :filename.split(~c"foo/bar") == [~c"foo", ~c"bar"]
    end

    test "charlist input with absolute path" do
      assert :filename.split(~c"/usr/local/bin") == [~c"/", ~c"usr", ~c"local", ~c"bin"]
    end

    test "atom input" do
      assert :filename.split(:"foo/bar") == [~c"foo", ~c"bar"]
    end

    test "empty list input" do
      assert :filename.split([]) == []
    end

    test "iolist input" do
      assert :filename.split([~c"foo", ?/, ~c"bar"]) == [~c"foo", ~c"bar"]
    end

    test "binary with invalid UTF-8 bytes" do
      # <<0xFF, 0xFE>> is invalid UTF-8
      filename = <<"usr/", 0xFF, 0xFE, "/bin">>

      # Should preserve invalid UTF-8 bytes
      expected = ["usr", <<0xFF, 0xFE>>, "bin"]

      assert :filename.split(filename) == expected
    end

    test "iolist with invalid UTF-8 bytes" do
      # Pure charlist: [117, 115, 114, 47, 0xFF, 0xFE, 47, 98, 105, 110]
      # "usr/" + [0xFF, 0xFE] + "/bin"
      filename = [?u, ?s, ?r, ?/, 0xFF, 0xFE, ?/, ?b, ?i, ?n]

      # Should return raw bytes as integers: [[117, 115, 114], [0xFF, 0xFE], [98, 105, 110]]
      expected = [~c"usr", [0xFF, 0xFE], ~c"bin"]

      assert :filename.split(filename) == expected
    end

    test "raises FunctionClauseError if the argument is not a valid filename type" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.split(123) end
    end
  end
end
