# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module185 do
  use Hologram.Component

  prop :row, :any

  @impl Component
  def template do
    ~HOLO"""
    layout = {inspect(@row.token)}; <slot />
    """
  end
end
