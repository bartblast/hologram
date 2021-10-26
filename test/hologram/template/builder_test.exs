defmodule Hologram.Template.BuilderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.Builder
  alias Hologram.Template.VDOM.{Component, ElementNode, TextNode}

  @module_1 Hologram.Test.Fixtures.Template.Builder.Module1
  @module_2 Hologram.Test.Fixtures.Template.Builder.Module2
  @module_3 Hologram.Test.Fixtures.Template.Builder.Module3

  describe "build/1" do
    test "without layout" do
      result = Builder.build(@module_1)
      assert [%ElementNode{}, %TextNode{}, %Component{module: @module_2}] = result
    end

    test "with layout" do
      result = Builder.build(@module_1, @module_3)

      assert [
               %Component{
                 children: [
                   %ElementNode{},
                   %TextNode{},
                   %Component{
                     module: @module_2
                   }
                 ],
                 module: @module_3
               }
             ] = result
    end
  end
end
