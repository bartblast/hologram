# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module162 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15

  derived :entities, [Module15], fn -> sort(Module15, label) end

  @impl Component
  def template do
    ~HOLO"""
    labels = {Enum.map_join(@entities, ",", & &1.label)}
    secret_note = {inspect(hd(@entities).secret_note)}
    token = {inspect(hd(@entities).token)}
    """
  end
end
