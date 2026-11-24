defmodule HologramFeatureTests.EntityImpls.Page1 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Crate

  route "/entity-impls/1"

  layout HologramFeatureTests.Components.DefaultLayout

  # Names Crate only. Bottle reaches the page through the relationship, and no browser code names
  # it, so printing one needs the String.Chars implementation of a type the page holds only by row.
  derived :crates, [Crate], fn ->
    Crate
    |> include(bottles)
    |> sort(name)
  end

  def template do
    ~HOLO"""
    <p>
      Crates: <strong id="crates"><code>{Enum.map_join(@crates, ";", fn crate -> "#{crate.name}:#{Enum.map_join(crate.bottles, ",", fn bottle -> "#{bottle}" end)}" end)}</code></strong>
    </p>
    """
  end
end
