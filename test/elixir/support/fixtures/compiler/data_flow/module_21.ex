# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module21 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module22
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module23
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def calls_dispatch(flag), do: dispatch(if flag, do: Module22, else: Module23)

  def calls_twice, do: twice({%Struct1{}, %Struct1{}, %Struct1{}, %Struct1{}}, &repeat/1)

  def calls_wrap, do: wrap({%Struct1{}, %Struct1{}, %Struct1{}, %Struct1{}})

  def dispatch(module), do: {module.value(), :done}

  def nested do
    value = {%Struct1{}, %Struct1{}, %Struct1{}, %Struct1{}}
    {value, value, value, value}
  end

  def repeat(value), do: {value, value, value, value}

  def twice(value, fun) do
    value
    |> fun.()
    |> fun.()
  end

  def wrap(value), do: {:ok, value}
end
