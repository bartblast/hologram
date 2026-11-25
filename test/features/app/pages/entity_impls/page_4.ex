defmodule HologramFeatureTests.EntityImpls.Page4 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Jar

  route "/entity-impls/4"

  layout HologramFeatureTests.Components.DefaultLayout

  derived :jars, [Jar], fn ->
    Jar
    |> include(pantry)
    |> sort(label)
  end

  # Builds a struct from the module a row holds. The page never names Pantry, which has no protocol
  # implementation, so none of its code is loaded.
  def template do
    ~HOLO"""
    <p>
      Jars: <strong id="jars"><code>{Enum.map_join(@jars, ",", fn jar -> "#{jar.label}:#{struct(jar.pantry.__struct__, name: "copy").name}" end)}</code></strong>
    </p>
    """
  end
end
