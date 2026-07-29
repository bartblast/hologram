# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module38 do
  def my_fun_1 do
    raise ArgumentError, "my message"
  end

  def my_fun_2 do
    raise "my message"
  end
end
