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

  # See interpreter "inspect" consistency tests
  # describe "inspect/2"
end
