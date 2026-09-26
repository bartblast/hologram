# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module19 do
  def field(value), do: value.title

  def nested(value), do: elem(elem(value, 0), 0)

  def single(value), do: elem(value, 0)
end
