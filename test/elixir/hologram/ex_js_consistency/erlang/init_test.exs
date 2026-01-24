defmodule Hologram.ExJsConsistency.Erlang.InitTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/init_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "get_argument/1" do
    test ":home flag" do
      assert {:ok, [[home_path]]} = :init.get_argument(:home)
      assert is_list(home_path)
    end

    test ":progname flag" do
      assert :init.get_argument(:progname) == {:ok, [[~c"erl"]]}
    end

    test ":root flag" do
      assert {:ok, [[root_path]]} = :init.get_argument(:root)
      assert is_list(root_path)
    end

    test "unknown flag" do
      assert :init.get_argument(:my_nonexistent_flag) == :error
    end

    test "argument is nil" do
      assert :init.get_argument(nil) == :error
    end

    test "argument is not an atom" do
      assert :init.get_argument(1) == :error
    end
  end
end
