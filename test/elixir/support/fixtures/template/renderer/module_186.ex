# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module186 do
  use Hologram.Component

  prop :row, :any

  @impl Component
  def template do
    ~HOLO"""
    stateless = {inspect(@row.token)}
    """
  end
end
