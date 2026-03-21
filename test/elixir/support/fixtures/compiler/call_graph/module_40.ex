# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module40 do
  def my_fun do
    :ok
  rescue
    ArgumentError -> :error
  end
end
