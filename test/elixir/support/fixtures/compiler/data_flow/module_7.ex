# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module7 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def count(list), do: Enum.count(list)

  def first_part(text) do
    [first | _rest] = String.split(text, ",")
    first
  end

  def inspects, do: inspect(%Struct1{})

  def interpolates(value), do: "value: #{value}"

  def pairs_with_parts(text) do
    pairs = for part <- String.split(text, ","), do: {part, %Struct1{}}
    [{_part, struct} | _rest] = pairs
    struct
  end

  def raises, do: raise(ArgumentError, "no")

  def raises_or_struct(value) do
    if value, do: %Struct1{}, else: raise(ArgumentError, "no")
  end

  def to_string_of(value), do: to_string(value)
end
