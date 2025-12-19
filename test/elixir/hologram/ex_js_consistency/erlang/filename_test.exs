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

    test "list of code points for atom input" do
      assert :filename.basename(:"path/to/file.txt") == ~c"file.txt"
    end

    test "list of code points for atom input with single segment" do
      assert :filename.basename(:filename) == ~c"filename"
    end

    test "list of code points for nil atom input" do
      assert :filename.basename(nil) == ~c"nil"
    end

    test "returns empty list for empty list input" do
      assert :filename.basename([]) == []
    end

    test "list of code points for non-empty list input" do
      assert :filename.basename([~c"path/to/", ?f, ?i, ?l, ?e, ~c".txt"]) == ~c"file.txt"
    end

    test "list of code points for list input with single segment" do
      assert :filename.basename([?f, ?i, ?l, ?e, ?n, ?a, ?m, ?e]) == ~c"filename"
    end

    test "raises FunctionClauseError if the argument is not a binary or atom or list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.basename(123) end
    end

    test "raises FunctionClauseError if the argument is a non-binary bitstring" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [
                     <<1::1, 0::1, 3::2>>,
                     []
                   ]),
                   fn -> :filename.basename(<<1::1, 0::1, 3::2>>) end
    end
  end
end
