defprotocol HologramFeatureTests.PantryReport do
  def sealed_lids(row)
end

defimpl HologramFeatureTests.PantryReport, for: HologramFeatureTests.Entities.Jar do
  use Hologram.DB

  alias HologramFeatureTests.Entities.Lid

  def sealed_lids(_jar) do
    Lid
    |> filter(sealed == true)
    |> count()
  end
end
