defmodule Hologram.Test.Fixtures.Commons.Reflection.Module5 do
  defstruct []
end

defimpl String.Chars, for: Hologram.Test.Fixtures.Commons.Reflection.Module5 do
  def to_string(_value), do: "..."
end
