defmodule Hologram.Assets.Pipeline.TailwindTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Assets.Pipeline.Tailwind

  describe "installed?/0" do
    test "returns true when Tailwind is available" do
      # Tailwind is available in test env (by mix.exs)
      assert installed?() == true
    end

    # We can't test this case
    # test "returns false when Tailwind is not available"
  end
end
