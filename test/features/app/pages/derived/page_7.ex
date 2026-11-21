defmodule HologramFeatureTests.Derived.Page7 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Crate

  route "/derived/7"

  layout HologramFeatureTests.Components.DefaultLayout

  derived :crates, [Crate], fn ->
    Crate
    |> include(bottles)
    |> sort(name)
  end

  def template do
    ~HOLO"""
    <p>
      Crates: <strong id="crates"><code>{Enum.map_join(@crates, ";", fn crate -> "#{crate.name}:#{Enum.map_join(crate.bottles, ",", & &1.label)}" end)}</code></strong>
    </p>
    """
  end
end
