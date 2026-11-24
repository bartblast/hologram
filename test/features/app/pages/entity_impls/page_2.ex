defmodule HologramFeatureTests.EntityImpls.Page2 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Pantry
  alias HologramFeatureTests.PantryReport

  route "/entity-impls/2"

  layout HologramFeatureTests.Components.DefaultLayout

  derived :pantries, [Pantry], fn ->
    Pantry
    |> include(jars)
    |> sort(name)
  end

  # Dispatches on a Jar, which the page reaches only by the relationship name. Only that
  # implementation names Lid.
  derived :sealed_lids, :integer, fn pantries ->
    case pantries do
      [%{jars: [jar | _jars]} | _pantries] -> PantryReport.sealed_lids(jar)
      _no_jar -> 0
    end
  end

  def template do
    ~HOLO"""
    <p>
      Sealed lids: <strong id="sealed_lids"><code>{@sealed_lids}</code></strong>
    </p>
    """
  end
end
