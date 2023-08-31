defmodule Hologram.Test.Fixtures.Template.Renderer.Module22 do
  use Hologram.Layout

  @impl Layout
  def template do
    ~H"<slot />"
  end
end
