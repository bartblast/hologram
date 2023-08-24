defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Renderer

  test "multiple nodes" do
    nodes = [{:text, "abc"}, {:text, "xyz"}]
    assert render(nodes) == "abcxyz"
  end

  test "expression" do
    node = {:expression, {123}}
    assert render(node) == "123"
  end

  test "text" do
    node = {:text, "abc"}
    assert render(node) == "abc"
  end
end
