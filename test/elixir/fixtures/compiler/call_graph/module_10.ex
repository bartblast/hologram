# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module10 do
  def my_fun_c do
    my_fun_d()
  end

  def my_fun_d do
    :ok
  end
end
