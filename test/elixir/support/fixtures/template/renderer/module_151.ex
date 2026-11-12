defmodule Hologram.Test.Fixtures.Template.Renderer.Module151 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :ripe, [Entity2], fn ->
    Entity2
    |> filter(a == true)
    |> sort(c)
  end

  # A count reading another derived field's rows, so the arguments it is carried under hold rows.
  derived :ripe_total, :integer, fn ripe ->
    ids = Enum.map(ripe, & &1.id)

    Entity2
    |> filter(id in ^ids)
    |> count()
  end

  @impl Component
  def template do
    ~HOLO"ripe = {@ripe_total}"
  end
end
