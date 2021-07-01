defmodule Hologram.Template.VirtualDOMTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM
  alias Hologram.Template.VirtualDOM.{Component, ElementNode, TextNode}

  test "build/1" do
    module = Hologram.Test.Fixtures.Template.VirtualDOM.Module1
    aliased_module = [:Hologram, :Test, :Fixtures, :Template, :VirtualDOM, :Module2]
    result = VirtualDOM.build(module)

    assert [%ElementNode{}, %TextNode{}, %Component{module: ^aliased_module}] = result
  end
end
