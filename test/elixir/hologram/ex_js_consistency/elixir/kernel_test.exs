defmodule Hologram.ExJsConsistency.Elixir.KernelTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/kernel_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "inspect/1" do
    test "delegates to inspect/2" do
      assert Kernel.inspect(true) == "true"
    end
  end

  # Also see interpreter "inspect" consistency tests
  test "inspect/2" do
    assert Kernel.inspect(%{b: 2, a: 1}, custom_options: [sort_maps: true]) == "%{a: 1, b: 2}"
  end
end
