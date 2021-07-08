defmodule Hologram.Template.BuilderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Builder
  alias Hologram.Template.Document.{Component, ElementNode, TextNode}

  test "build/1" do
    module = Hologram.Test.Fixtures.Template.Builder.Module1
    aliased_module = [:Hologram, :Test, :Fixtures, :Template, :Builder, :Module2]
    result = Builder.build(module)

    assert [%ElementNode{}, %TextNode{}, %Component{module: ^aliased_module}] = result
  end
end
