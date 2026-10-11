# Sent in a broadcast by the command of the pushed structs page, and referenced by no other app
# code, so that no tab holds its chunks before the broadcast arrives. Referencing the struct
# anywhere else would silently stop testing that.
defmodule HologramFeatureTests.PushedStructFixture do
  defstruct name: "fixture"
end

defimpl String.Chars, for: HologramFeatureTests.PushedStructFixture do
  def to_string(data) do
    "pushed struct(#{data.name})"
  end
end
