# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module20 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def deleted, do: Map.delete(%Struct1{}, :field)

  def merged, do: Map.merge(%Struct1{}, %{field: 1})

  def put, do: Map.put(%Struct1{}, :field, 1)

  def read_field(%Struct1{} = value), do: value.field

  def read_fields(%{} = value), do: [value.a, value.b, value.c]

  def read_struct(%Struct1{} = value), do: value.__struct__

  def updated, do: %Struct1{%Struct1{} | field: 1}
end
