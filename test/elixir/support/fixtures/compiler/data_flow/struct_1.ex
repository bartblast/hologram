# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Struct1 do
  defstruct [:field]
end

defimpl String.Chars, for: Hologram.Test.Fixtures.Compiler.DataFlow.Struct1 do
  def to_string(_struct), do: "struct 1"
end
