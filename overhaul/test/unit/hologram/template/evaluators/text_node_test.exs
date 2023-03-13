defmodule Hologram.Template.Evaluator.TextNodeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.Evaluator
  alias Hologram.Template.VDOM.TextNode

  test "evaluate/2" do
    node = %TextNode{content: "abc"}

    result = Evaluator.evaluate(node, %{})
    expected = "abc"

    assert result == expected
  end
end
