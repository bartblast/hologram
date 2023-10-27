# credo:disable-for-this-file Credo.Check.Readability.Specs

defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module12 do
  defstruct []
end

defimpl String.Chars, for: Hologram.Test.Fixtures.Compiler.CallGraph.Module12 do
  @spec to_string(String.t()) :: String.t()
  def to_string(_value), do: "..."
end
