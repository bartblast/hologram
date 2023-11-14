defmodule Hologram.ExJsConsistency.Elixir.KernelTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/kernel_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe "inspect/2" do
    test "atom, true" do
      assert Kernel.inspect(true, []) == "true"
    end

    test "atom, false" do
      assert Kernel.inspect(false, []) == "false"
    end

    test "atom, nil" do
      assert Kernel.inspect(nil, []) == "nil"
    end

    test "atom, non-boolean and non-nil" do
      assert Kernel.inspect(:abc, []) == ":abc"
    end
  end
end
