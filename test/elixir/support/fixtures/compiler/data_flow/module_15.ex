# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module15 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def inner(acc, n) do
    case n do
      0 -> acc
      1 -> outer(acc, n - 1)
      _n -> wrap(acc, n)
    end
  end

  def outer(acc, n), do: inner(acc, n)

  def ring_a(x), do: {ring_b(x), ring_c(x)}

  def ring_b(x), do: {ring_c(x), ring_d(x)}

  def ring_c(x), do: {ring_d(x), ring_a(x)}

  def ring_d(0), do: %Struct1{}

  def ring_d(x), do: {ring_a(x), ring_b(x)}

  def wrap(acc, n), do: inner([%Struct1{} | acc], n - 1)
end
