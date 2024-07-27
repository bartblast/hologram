# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module100 do
  def test(anon_fun) do
    anon_fun.(1, 2).remote_fun(3, 4)
  end
end
