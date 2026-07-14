defmodule HologramFeatureTests.StructFixture4 do
  defstruct name: "fixture"
end

defimpl String.Chars, for: HologramFeatureTests.StructFixture4 do
  def to_string(data) do
    "command struct(#{data.name})"
  end
end
