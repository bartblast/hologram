# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module99 do
  def test(anon_fun) do
    anon_fun.(1, 2).remote_fun()
  end
end
