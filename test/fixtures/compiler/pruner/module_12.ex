defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module12 do
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module13

  def some_fun_1 do
    Module13.some_fun_2()
  end
end
