defmodule HologramFeatureTests.AnsweredPairsPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Binder
  alias HologramFeatureTests.Entities.Decal

  route "/answered-pairs"

  layout HologramFeatureTests.Components.DefaultLayout

  derived :binders, [Binder], &binders_query/0
  derived :decals, [Decal], &decals_query/0

  def template do
    ~HOLO"""
    <p>
      <button $click="add_decal"> Add decal </button>
    </p>
    <p>
      Binders: <strong id="binders"><code>{Enum.map_join(@binders, " ", &summary/1)}</code></strong>
    </p>
    <p>
      Decals: <strong id="decals"><code>{Enum.map_join(@decals, ",", & &1.name)}</code></strong>
    </p>
    """
  end

  # Runs in the browser, so the batch adding the pair can wait while the decal leaves it.
  def action(:add_decal, _params, component) do
    decal =
      Decal
      |> one()
      |> DB.read()

    Binder
    |> filter(name == "main")
    |> one()
    |> DB.read()
    |> add_relationship(:decals, decal.id)
    |> DB.update!()

    component
  end

  def summary(binder) do
    binder.name <>
      "(" <> binder.note <> ")[" <> Enum.map_join(binder.decals, ",", & &1.name) <> "]"
  end

  defp binders_query do
    Binder
    |> include(decals)
    |> sort(name)
  end

  defp decals_query do
    Decal
  end
end
