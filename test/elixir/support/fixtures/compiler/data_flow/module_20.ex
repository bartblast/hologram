# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module20 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def deleted, do: Map.delete(%Struct1{}, :field)

  def merged, do: Map.merge(%Struct1{}, %{field: 1})

  def put, do: Map.put(%Struct1{}, :field, 1)

  def updated, do: %Struct1{%Struct1{} | field: 1}
end
