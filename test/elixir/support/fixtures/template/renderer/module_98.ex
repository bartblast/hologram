# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module98 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"<div><span>a</span></div><p>b</p>"
  end
end
