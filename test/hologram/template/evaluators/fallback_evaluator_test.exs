defmodule Hologram.Template.FallbackEvaluatorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    assert Evaluator.evaluate("str", %{}) == "str"
  end
end
