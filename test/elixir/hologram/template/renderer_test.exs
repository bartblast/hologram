defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Renderer

  test "text" do
    node = {:text, "abc"}
    assert render(node) == "abc"
  end
end
