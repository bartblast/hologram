# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module18 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  for index <- 0..68 do
    def unquote(:"chain_#{index}")(value), do: unquote(:"chain_#{index + 1}")(value)
  end

  def chain_69(_value), do: %Struct1{}

  # Each pair nests its first element one level deeper on every evaluation until widened, and holds
  # steady's answer or a struct; steady gives the pairs' second elements, so its answer is the struct
  # however many times the pairs change.
  for name <- [:pair_a, :pair_b, :pair_c, :pair_d, :pair_e, :pair_f, :pair_g] do
    def unquote(name)(0), do: {nil, %Struct1{}}

    def unquote(name)(value) do
      {first, _second} = unquote(name)(value - 1)
      {{first}, steady(value)}
    end
  end

  def pairs(value) do
    [
      pair_a(value),
      pair_b(value),
      pair_c(value),
      pair_d(value),
      pair_e(value),
      pair_f(value),
      pair_g(value)
    ]
  end

  def steady(value) do
    {_first_a, a} = pair_a(value - 1)
    {_first_b, b} = pair_b(value - 1)
    {_first_c, c} = pair_c(value - 1)
    {_first_d, d} = pair_d(value - 1)
    {_first_e, e} = pair_e(value - 1)
    {_first_f, f} = pair_f(value - 1)
    {_first_g, g} = pair_g(value - 1)

    case value do
      1 -> a
      2 -> b
      3 -> c
      4 -> d
      5 -> e
      6 -> f
      _value -> g
    end
  end

  def stepped(_module, 0 = value), do: value

  def stepped(module, value), do: stepped(module, module.step(value))

  def wrapped(module, 0), do: module

  def wrapped(module, count), do: wrapped(module, count - 1).wrap()
end
