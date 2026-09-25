# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module8 do
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def calls_modules, do: call_each([Module3])

  def call_each(modules), do: for(module <- modules, do: module.build())

  def enum_map, do: Enum.map([1, 2], fn count -> %Struct1{field: count} end)

  def enum_reduce do
    Enum.reduce([%Struct1{}], [], fn struct, acc -> [{struct, %Struct2{}} | acc] end)
  end

  def keyword_get, do: Keyword.get([struct: %Struct1{}], :struct)

  def map_get, do: Map.get(%{struct: %Struct1{}}, :struct)

  def map_put, do: Map.put(%{}, :struct, %Struct1{})

  def session_put(server), do: Server.put_session(server, :struct, %Struct1{})
end
