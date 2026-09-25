# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module5 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def calls_closure do
    fun = fn -> %Struct1{} end
    fun.()
  end

  def calls_closure_of_param, do: closure_of_param(%Struct1{}).()

  def calls_higher_order, do: higher_order(fn struct -> {struct, %Struct2{}} end)

  def capture_local do
    fun = &wrap/1
    fun.(%Struct1{})
  end

  def capture_remote do
    fun = &Module3.build/0
    fun.()
  end

  def closure, do: fn -> %Struct1{} end

  def closure_arg do
    fun = fn struct -> {:ok, struct} end
    fun.(%Struct1{})
  end

  def closure_clauses(value) do
    fun = fn
      :a -> %Struct1{}
      _other -> %Struct2{}
    end

    fun.(value)
  end

  def closure_free_variable do
    struct = %Struct1{}
    fun = fn -> struct end
    fun.()
  end

  def closure_of_param(value), do: fn -> value end

  def closure_shadowing_param(value) do
    fun = fn value -> {value} end
    {value, fun.(%Struct1{})}
  end

  def higher_order(fun), do: fun.(%Struct1{})

  def recursive_closure([_head | tail]), do: recursive_closure(tail)

  def recursive_closure([]), do: fn -> %Struct1{} end

  defp wrap(value), do: {:ok, value}
end
