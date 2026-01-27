defmodule Hologram.ExJsConsistency.Erlang.FilelibTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/filelib_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "safe_relative_path/2" do
    test "relative path with single component" do
      assert :filelib.safe_relative_path("dir", "/home/user") == "dir"
    end

    test "relative path with multiple components" do
      assert :filelib.safe_relative_path("dir/sub_dir", "/home/user") == "dir/sub_dir"
    end

    test "relative path with .. that stays within bounds" do
      assert :filelib.safe_relative_path("dir/sub_dir/..", "/home/user") == "dir"
    end

    test "relative path with .. that returns to root" do
      assert :filelib.safe_relative_path("dir/..", "/home/user") == []
    end

    test "relative path with .. that escapes root" do
      assert :filelib.safe_relative_path("dir/../..", "/home/user") == :unsafe
    end

    test "absolute path" do
      assert :filelib.safe_relative_path("/abs/path", "/home/user") == :unsafe
    end

    test "relative path with . components" do
      assert :filelib.safe_relative_path("./dir/./sub", "/home/user") == "dir/sub"
    end

    test "empty path" do
      assert :filelib.safe_relative_path("", "/home/user") == []
    end

    test "charlist relative path" do
      assert :filelib.safe_relative_path(~c"dir", ~c"/") == ~c"dir"
    end

    test "charlist path with .." do
      assert :filelib.safe_relative_path(~c"dir/..", ~c"/") == []
    end

    test "charlist path escaping root" do
      assert :filelib.safe_relative_path(~c"dir/../..", ~c"/") == :unsafe
    end

    test "cwd with empty string is normalized to dot" do
      assert :filelib.safe_relative_path("dir", "") == "dir"
    end

    test "cwd with empty list is normalized to dot" do
      assert :filelib.safe_relative_path(~c"dir", []) == ~c"dir"
    end

    test "path with multiple consecutive .. components" do
      assert :filelib.safe_relative_path("a/b/c/../../..", "/home") == []
    end

    test "path with multiple consecutive .. that escapes" do
      assert :filelib.safe_relative_path("a/b/../../../../", "/home") == :unsafe
    end

    test "path with trailing slashes" do
      assert :filelib.safe_relative_path("dir/sub/", "/home") == "dir/sub"
    end

    test "path with only . components" do
      assert :filelib.safe_relative_path("./.././.", "/home") == :unsafe
    end

    test "binary input" do
      assert :filelib.safe_relative_path(<<"dir">>, <<"/home">>) == <<"dir">>
    end

    test "mixed binary and charlist" do
      # Elixir will handle this appropriately
      assert :filelib.safe_relative_path("dir", ~c"/home") == "dir"
    end

    test "invalid utf-8 bytes" do
      result = :filelib.safe_relative_path(<<0xFF, 0xFE>>, "/home")
      assert result == <<0xFF, 0xFE>>
    end

    test "cwd with invalid type" do
      assert_raise FunctionClauseError, fn ->
        :filelib.safe_relative_path("dir", 123)
      end
    end

    test "cwd with valid atom type" do
      assert :filelib.safe_relative_path("dir", :ok) == "dir"
    end
  end
end
