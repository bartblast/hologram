defmodule Hologram.Runtime.CommonsTest do
  use Hologram.Test.UnitCase, async: true
  require Hologram.Runtime.Commons

  alias Hologram.Runtime.Commons
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Template.VDOM.TextNode

  test "sigil_H/2" do
    result = Commons.sigil_H("<div>abc</div>", [])

    expected = [
      %ElementNode{
        attrs: %{},
        children: [%TextNode{content: "abc"}],
        tag: "div"
      }
    ]

    assert result == expected
  end
end
