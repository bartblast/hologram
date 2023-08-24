defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Renderer

  test "text" do
    node = {:text, "abc"}
    assert render(node) == "abc"
  end

  test "multiple nodes" do
    nodes = [{:text, "abc"}, {:text, "xyz"}]
    assert render(nodes) == "abcxyz"
  end
end
