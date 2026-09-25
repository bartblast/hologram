# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module16 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def encode(value, list?) do
    encode_map = if list?, do: &wrap_list/2, else: &wrap_tuple/2
    value(value, encode_map)
  end

  def value(value, encode_map) do
    case value do
      %{} -> encode_map.(value, encode_map)
      _other -> value
    end
  end

  def wrap_list(value, encode_map), do: [value(value, encode_map)]

  def wrap_tuple(value, encode_map), do: {%Struct1{}, value(value, encode_map)}
end
