# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module21 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def calls_twice, do: twice({%Struct1{}, %Struct1{}, %Struct1{}, %Struct1{}}, &repeat/1)

  def repeat(value), do: {value, value, value, value}

  def twice(value, fun) do
    value
    |> fun.()
    |> fun.()
  end
end
