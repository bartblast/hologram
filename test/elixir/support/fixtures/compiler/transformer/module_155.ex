# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module155 do
  def test do
    &my_fun/0
  end

  def my_fun, do: :ok
end
