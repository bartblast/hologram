# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module9 do
  def my_fun_a do
    my_fun_b()
  end

  def my_fun_b do
    :ok
  end
end
