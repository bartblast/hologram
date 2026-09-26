# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module21 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module22
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module23
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def calls_dispatch(flag), do: dispatch(if flag, do: Module22, else: Module23)

  def calls_twice, do: twice({{:u}, {:v}, {:w}, {:x}, {:y}, {:z}}, &spread/1)

  def calls_wrap, do: wrap({{:a}, {:b}, {:c}, {:d}, {:e}, {:f}})

  def dispatch(module), do: {module.value(), :done}

  def nested do
    value = {%Struct1{}, %Struct1{}, %Struct1{}, %Struct1{}}
    {value, value, value, value}
  end

  def spread(value),
    do: {{:a, value}, {:b, value}, {:c, value}, {:d, value}, {:e, value}, {:f, value}}

  def twice(value, fun) do
    value
    |> fun.()
    |> fun.()
  end

  def wrap(value), do: {:ok, value}
end
