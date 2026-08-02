defmodule HologramFeatureTests.StructFixture5 do
  defstruct name: "fixture"
end

defimpl String.Chars, for: HologramFeatureTests.StructFixture5 do
  def to_string(data) do
    "broadcast struct(#{data.name})"
  end
end
