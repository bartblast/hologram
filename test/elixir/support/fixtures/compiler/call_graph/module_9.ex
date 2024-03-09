# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module9 do
  def my_fun_1 do
    my_fun_2()
  end

  def my_fun_2 do
    :ok
  end
end
