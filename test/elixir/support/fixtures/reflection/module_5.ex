# credo:disable-for-this-file Credo.Check.Readability.Specs

defmodule Hologram.Test.Fixtures.Reflection.Module5 do
  defstruct []
end

defimpl String.Chars, for: Hologram.Test.Fixtures.Reflection.Module5 do
  def to_string(_value), do: "..."
end
