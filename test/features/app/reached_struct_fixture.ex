# Put in the state by the server code of the transient server structs page, and rendered on the
# client, so its String.Chars implementation must reach the client.
defmodule HologramFeatureTests.ReachedStructFixture do
  defstruct name: "fixture"
end

defimpl String.Chars, for: HologramFeatureTests.ReachedStructFixture do
  def to_string(data) do
    "reached(#{data.name})"
  end
end
