# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module168 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module33

  derived :vaults, [Module33], fn -> Module33 end

  @impl Component
  def template do
    ~HOLO"""
    vaults = {length(@vaults)}
    """
  end
end
