defprotocol HologramFeatureTests.ProtocolFixture do
  def format(data)
end

defimpl HologramFeatureTests.ProtocolFixture, for: Atom do
  def format(data) do
    "atom(#{data})"
  end
end

defimpl HologramFeatureTests.ProtocolFixture, for: HologramFeatureTests.StructFixture1 do
  def format(data) do
    "<<#{data.value}|#{data.name}>>"
  end
end
