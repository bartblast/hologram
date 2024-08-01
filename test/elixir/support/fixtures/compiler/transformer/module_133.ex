# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module133 do
  def test do
    1
  catch
    :exit, :timeout -> :error
  end
end
