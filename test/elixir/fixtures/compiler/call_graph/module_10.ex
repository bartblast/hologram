# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module10 do
  def my_fun_3 do
    my_fun_4()
  end

  def my_fun_4 do
    :ok
  end
end
