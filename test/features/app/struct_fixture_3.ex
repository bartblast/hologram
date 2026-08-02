defmodule HologramFeatureTests.StructFixture3 do
  defstruct name: "fixture"
end

defimpl String.Chars, for: HologramFeatureTests.StructFixture3 do
  def to_string(data) do
    "struct(#{data.name})"
  end
end
