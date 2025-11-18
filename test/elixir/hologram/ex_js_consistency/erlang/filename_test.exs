defmodule Hologram.ExJsConsistency.Erlang.FilenameTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/filename_test.mjs
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "basename/1" do
    test "returns basename for path with multiple segments" do
      assert :filename.basename("path/to/file.txt") == "file.txt"
    end

    test "returns basename for path with single segment" do
      assert :filename.basename("file.txt") == "file.txt"
    end

    test "returns basename for path with absolute path" do
      assert :filename.basename("/absolute/path/to/file.txt") == "file.txt"
    end

    test "returns basename for path ending with slash" do
      assert :filename.basename("path/to/dir/") == "dir"
    end

    test "returns basename for root path" do
      assert :filename.basename("/") == ""
    end

    test "returns basename for empty string" do
      assert :filename.basename("") == ""
    end

    test "returns basename for path with multiple consecutive slashes" do
      assert :filename.basename("path//to//file.txt") == "file.txt"
    end

    test "returns basename for path with only slashes" do
      assert :filename.basename("///") == ""
    end

    test "returns basename for path without extension" do
      assert :filename.basename("path/to/filename") == "filename"
    end

    test "returns basename for path with unicode characters" do
      assert :filename.basename("path/to/文件.txt") == "文件.txt"
    end

    test "returns basename for path with special characters" do
      assert :filename.basename("path/to/file-name_123.txt") == "file-name_123.txt"
    end

    test "returns basename as list of code points for atom input" do
      assert :filename.basename(:"path/to/file.txt") == ~c"file.txt"
    end

    test "returns basename as list of code points for atom input with single segment" do
      assert :filename.basename(:filename) == ~c"filename"
    end

    test "returns basename as list of code points for nil atom input" do
      assert :filename.basename(nil) == ~c"nil"
    end

    test "returns basename as list of code points for nil atom input with path" do
      assert :filename.basename(:"path/to/nil") == ~c"nil"
    end

    test "returns basename as list of code points for atom input with unicode characters" do
      assert :filename.basename(:"path/to/文件.txt") == ~c"文件.txt"
    end

    test "returns empty list for empty list input" do
      assert :filename.basename([]) == []
    end

    test "returns basename as list of code points for non-empty list input" do
      assert :filename.basename([~c"path/to/", ?f, ?i, ?l, ?e, ~c".txt"]) == ~c"file.txt"
    end

    test "returns basename as list of code points for list input with single segment" do
      assert :filename.basename([?f, ?i, ?l, ?e, ?n, ?a, ?m, ?e]) == ~c"filename"
    end

    test "raises FunctionClauseError if the argument is not a binary or atom" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.basename(123) end
    end

    test "raises FunctionClauseError if the argument is a tuple" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [{1, 2}, []]),
                   fn -> :filename.basename({1, 2}) end
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
