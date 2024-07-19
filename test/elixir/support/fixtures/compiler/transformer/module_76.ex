# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module76 do
  def my_fun(x) when is_integer(x) when x > 1 when x < 9 do
    x
  end
end
