defmodule Hologram.Template.TextNodeEvaluatorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    node = %TextNode{content: "abc"}

    result = Evaluator.evaluate(node, %{})
    expected = "abc"

    assert result == expected
  end
end
