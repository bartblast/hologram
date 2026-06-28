# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module181 do
  def test do
    # credo:disable-for-lines:5 Credo.Check.Readability.PreferImplicitTry
    try do
      1
    rescue
      _exception -> __STACKTRACE__
    end
  end
end
