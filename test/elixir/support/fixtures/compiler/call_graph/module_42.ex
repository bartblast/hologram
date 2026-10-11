# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module42 do
  def my_fun(module), do: module.__changeset__()
end
