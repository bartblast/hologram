# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module122 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module33

  prop :vaults, [Module33], from_query: &vaults_query/0

  @impl Component
  def template do
    ~HOLO"""
    vaults = {length(@vaults)}
    """
  end

  defp vaults_query do
    Module33
  end
end
