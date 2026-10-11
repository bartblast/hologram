# Built and dropped in the server code of the transient server structs page, and referenced by no
# other app code: the page only renders the text its String.Chars implementation gives on the
# server. So the implementation must be in neither the runtime nor a page bundle, only in a chunk,
# and the page must load none of the struct's chunks. Referencing the struct anywhere else would
# silently stop testing that.
defmodule HologramFeatureTests.TransientStructFixture do
  defstruct name: "fixture"
end

defimpl String.Chars, for: HologramFeatureTests.TransientStructFixture do
  def to_string(data) do
    "transient(#{data.name})"
  end
end
