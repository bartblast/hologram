# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module95 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15

  prop :entities, [Module15], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO"""
    labels = {Enum.map_join(@entities, ",", & &1.label)}
    secret_note = {inspect(hd(@entities).secret_note)}
    token = {inspect(hd(@entities).token)}
    """
  end

  defp entities_query do
    order_by(Module15, :label)
  end
end
