# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module17 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def calls_repeat, do: repeat(%Struct1{})

  def repeat(value), do: {value, value, value, value}
end
