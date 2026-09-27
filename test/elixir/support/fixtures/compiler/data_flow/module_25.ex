# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module25 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def calls_ruled, do: ruled()

  def calls_structs_of, do: structs_of(Struct1)

  def calls_structs_of_record, do: structs_of(%Struct1{})

  def calls_structs_of_nested, do: structs_of(%Struct1{field: %Struct2{}})

  def ruled, do: :followed

  def structs_of(module), do: module

  def structs_of_mixed(module, flag), do: structs_of(if flag, do: Struct1, else: module)
end
