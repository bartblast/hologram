defmodule Hologram.Template.BuilderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.Builder
  alias Hologram.Template.VDOM.{Component, ElementNode, TextNode}

  @module_1 Hologram.Test.Fixtures.Template.Builder.Module1
  @module_2 Hologram.Test.Fixtures.Template.Builder.Module2

  test "build/1" do
    result = Builder.build(@module_1)
    assert [%ElementNode{}, %TextNode{}, %Component{module: @module_2}] = result
  end
end
