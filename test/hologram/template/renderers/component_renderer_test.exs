defmodule Hologram.Template.ComponentRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.Component
  alias Hologram.Template.Renderer

  test "html only in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module1
    state = %{}

    result = Renderer.render(%Component{module: module}, state)
    expected = "<span>test</span>"

    assert result == expected
  end

  test "html and nested un-aliased component in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module2
    state = %{}

    result = Renderer.render(%Component{module: module}, state)
    expected = "<div><span>test</span></div>"

    assert result == expected
  end

  test "html and nested aliased component in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module3
    state = %{}

    result = Renderer.render(%Component{module: module}, state)
    expected = "<div><span>test</span></div>"

    assert result == expected
  end
end
