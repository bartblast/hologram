# No app code names this module: the unnamed struct page builds the struct from a string, so the
# compiler cannot see that it reaches the browser. It gets there with its String.Chars
# implementation all the same, since every struct type with an implementation of a protocol the
# client can call gets chunks, and the server names them when it meets the struct. Naming the
# module anywhere else would silently stop testing that.
defmodule HologramFeatureTests.UnnamedStructFixture do
  defstruct name: "fixture"
end

defimpl String.Chars, for: HologramFeatureTests.UnnamedStructFixture do
  def to_string(data) do
    "unnamed(#{data.name})"
  end
end
