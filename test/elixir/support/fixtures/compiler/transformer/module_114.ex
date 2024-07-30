# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module114 do
  defp test do
    :ok
  rescue
    e -> e
  end

  def my_fun do
    test()
  end
end
