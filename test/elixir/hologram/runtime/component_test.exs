defmodule Hologram.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

  test "H sigil" do
    template = ~H"""
    <div>{@value}</div>
    """

    assert template.(%{value: 123}) == [{:element, "div", [], [expression: {123}]}]
  end
end
