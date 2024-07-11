# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module32 do
  def my_fun(a, b, c) do
    [a] ++ [b] ++ c
  end
end
