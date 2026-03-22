defprotocol HologramFeatureTests.ProtocolFixture do
  def format(data)
end

defimpl HologramFeatureTests.ProtocolFixture, for: HologramFeatureTests.StructFixture do
  def format(data) do
    "<<#{data.value}|#{data.name}>>"
  end
end
