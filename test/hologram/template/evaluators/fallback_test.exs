defmodule Hologram.Template.Evaluator.FallbackTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    assert Evaluator.evaluate("str", %{}) == "str"
  end
end
