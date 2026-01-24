defmodule Hologram.ExJsConsistency.Erlang.InitTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/init_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "get_argument/1" do
    test "returns :error when flag is not set" do
      assert :init.get_argument(:my_nonexistent_flag) == :error
    end

    test "returns {:ok, Arg} for system flag :root" do
      assert {:ok, [[_root_path]]} = :init.get_argument(:root)
    end

    test "returns {:ok, Arg} for system flag :home" do
      assert {:ok, [[_home_path]]} = :init.get_argument(:home)
    end

    test "returns {:ok, Arg} for system flag :progname" do
      assert {:ok, [[_progname]]} = :init.get_argument(:progname)
    end

    test "returns :error for nil" do
      assert :init.get_argument(nil) == :error
    end

    test "returns :error if the argument is not an atom (integer)" do
      assert :init.get_argument(1) == :error
    end

    test "returns :error if the argument is not an atom (binary)" do
      assert :init.get_argument("my_flag") == :error
    end

    test "returns :error if the argument is not an atom (list)" do
      assert :init.get_argument([1, 2]) == :error
    end
  end
end
