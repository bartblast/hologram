defmodule Hologram.Template.ComponentRendererTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.ComponentRenderer

  test "render/2" do
    module = [:Hologram, :Test, :Fixtures, :Template, :ComponentRenderer, :Module1]
    state = %{}

    result = ComponentRenderer.render(module, state)
    expected = "<div>test</div>"

    assert result == expected
  end
end
