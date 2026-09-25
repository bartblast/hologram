# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.PreferImplicitTry
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module14 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def atom, do: :ok

  def map_literal, do: %{field: :value}

  def matched(%{} = map), do: map

  def param(value), do: value

  def raises, do: raise(ArgumentError, "no")

  def rescued(fun) do
    try do
      fun.()
      %{}
    rescue
      error -> error
    end
  end

  def struct_literal, do: %Struct1{}

  def validated(value), do: check(value)

  defp check(%{} = map), do: map
end
