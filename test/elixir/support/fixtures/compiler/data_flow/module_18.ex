# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module18 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  for index <- 0..68 do
    def unquote(:"chain_#{index}")(value), do: unquote(:"chain_#{index + 1}")(value)
  end

  def chain_69(_value), do: %Struct1{}

  def stepped(_module, 0 = value), do: value

  def stepped(module, value), do: stepped(module, module.step(value))

  def wrapped(module, 0), do: module

  def wrapped(module, count), do: wrapped(module, count - 1).wrap()
end
