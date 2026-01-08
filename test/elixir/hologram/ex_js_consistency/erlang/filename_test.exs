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

    test "atom input" do
      assert :filename.basename(:"path/to/file.txt") == ~c"file.txt"
    end

    test "empty list input" do
      assert :filename.basename([]) == []
    end

    test "non-empty iolist input" do
      assert :filename.basename([~c"path/to/", ?f, ?i, ?l, ?e, ~c".txt"]) == ~c"file.txt"
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
    test "binary input returns binary unchanged" do
      assert :filename.flatten("path/to/file.txt") == "path/to/file.txt"
    end

    test "atom input converts to charlist" do
      assert :filename.flatten(:myfile) == ~c"myfile"
    end

    test "flat list of integers returns as-is" do
      assert :filename.flatten([112, 97, 116, 104]) == [112, 97, 116, 104]
    end

    test "flat list with bitstring elements" do
      assert :filename.flatten([<<"foo">>, <<"bar">>]) == [<<"foo">>, <<"bar">>]
    end

    test "nested list with integers flattens correctly" do
      assert :filename.flatten([112, [97, 116], 104]) == [112, 97, 116, 104]
    end

    test "deeply nested list flattens correctly" do
      assert :filename.flatten([[[97, 98], 99], 100]) == [97, 98, 99, 100]
    end

    test "list with atom elements converts atoms to charcodes" do
      assert :filename.flatten([:foo, 47, :bar]) == [102, 111, 111, 47, 98, 97, 114]
    end

    test "empty list returns empty list" do
      assert :filename.flatten([]) == []
    end

    test "list with empty nested list" do
      assert :filename.flatten([97, [], 98]) == [97, 98]
    end

    test "mixed list with bitstrings, atoms, integers and nested lists" do
      assert :filename.flatten([<<"path">>, [47, :to], 47, [<<"file.txt">>]]) ==
               [<<"path">>, 47, 116, 111, 47, <<"file.txt">>]
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
end
